import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/customer_refund_model.dart';
import '../models/refund_issue_category_model.dart';
import '../models/refund_status_event_model.dart';
import '../models/refund_transaction_model.dart';
import '../models/refund_message_model.dart';
import '../models/booking_for_refund_model.dart';

class RefundQueriesService {
  // Same SharedPreferences key used by BookingsService and AuthService.
  static const _phoneKey = 'dodo_auth_phone';

  final _client = Supabase.instance.client;

  // Cached value from the last fetchBookingsForRefund call.  Used by
  // BookingSelectionScreen to evaluate isRefundPeriodExpired without an
  // extra RPC round-trip.  Defaults to 30 until the first fetch completes.
  int _lastFetchedRefundPeriodDays = 30;
  int get lastFetchedRefundPeriodDays => _lastFetchedRefundPeriodDays;

  static const _refundSelect = '''
    id, ticket_number, booking_id, customer_id, payment_id,
    issue_category_id, description, requested_amount,
    evidence_urls, evidence_count,
    payment_method_snapshot, amount_paid_snapshot,
    status, approved_amount, decision_notes,
    processed_amount, created_at, updated_at,
    bank_details_requested_at, bank_details_submitted_at,
    bookings(booking_number, service_date),
    refund_issue_categories(label)
  ''';

  // booking_payments is intentionally NOT embedded here.
  // PostgREST cannot reliably embed child tables from this project's DB setup
  // (the same limitation affects booking_addons in BookingsService).
  // payment_method from the bookings row is sufficient for display; the
  // server-side RPC resolves the actual payment_id when creating a ticket.
  static const _bookingForRefundSelect = '''
    id, booking_number, service_date, created_at, status,
    total_amount, payment_method, payment_status, notes, completed_at,
    booking_items(
      catalog_nodes!booking_items_service_id_catalog_fkey(id, name),
      vendor_service_requests!booking_items_custom_service_id_fkey(id, service_name)
    )
  ''';

  // ── Customer identity ─────────────────────────────────────────────────────
  // This project uses a custom phone-OTP flow (dev_auth) instead of Supabase
  // Auth, so auth.uid() is always NULL. Customer identity is derived from the
  // phone stored in SharedPreferences after OTP verification, exactly as
  // BookingsService does.

  Future<String> _getCustomerId() async {
    final phone =
        (await SharedPreferences.getInstance()).getString(_phoneKey);
    if (phone == null) throw Exception('Not authenticated');
    debugPrint('[Refund] _getCustomerId phone=$phone');
    final row = await _client
        .from('customers')
        .select('id')
        .eq('phone', phone)
        .single();
    final id = row['id'] as String;
    debugPrint('[Refund] _getCustomerId customer_id=$id');
    return id;
  }

  // ── Fetch my refund requests (all) ────────────────────────────────────────

  Future<List<CustomerRefundModel>> fetchMyRefundRequests() async {
    try {
      final customerId = await _getCustomerId();
      final data = await _client
          .from('refund_requests')
          .select(_refundSelect)
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);

      return (data as List<dynamic>)
          .map((r) =>
              CustomerRefundModel.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Refund] fetchMyRefundRequests error: $e\n$st');
      rethrow;
    }
  }

  // ── Fetch single request with full detail ─────────────────────────────────

  Future<CustomerRefundModel?> fetchRefundRequestById(String id) async {
    try {
      final customerId = await _getCustomerId();
      final data = await _client
          .from('refund_requests')
          .select(_refundSelect)
          .eq('id', id)
          .eq('customer_id', customerId)
          .maybeSingle();

      if (data == null) return null;

      final history = await _fetchStatusHistory(id);
      final txns = await _fetchTransactions(id);
      final msgs = await _fetchMessages(id);

      return CustomerRefundModel.fromMap(
        data,
        statusHistory: history,
        transactions: txns,
        messages: msgs,
      );
    } catch (e, st) {
      debugPrint('[Refund] fetchRefundRequestById error: $e\n$st');
      rethrow;
    }
  }

  // ── Fetch issue categories ─────────────────────────────────────────────────

  Future<List<RefundIssueCategoryModel>> fetchIssueCategories() async {
    final data = await _client
        .from('refund_issue_categories')
        .select('id, key, label, description, requires_evidence, sort_order')
        .eq('is_active', true)
        .order('sort_order');

    return (data as List<dynamic>)
        .map((r) =>
            RefundIssueCategoryModel.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  // ── Fetch refund policy description ───────────────────────────────────────

  Future<String?> fetchRefundPolicyDescription() async {
    try {
      final data = await _client
          .from('refund_policies')
          .select('description')
          .eq('applies_to', 'global')
          .eq('is_active', true)
          .order('priority')
          .limit(1)
          .maybeSingle();
      return data?['description'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ── Fetch global refund eligibility period ────────────────────────────────

  Future<int> fetchGlobalRefundPeriodDays() async {
    try {
      final row = await _client
          .from('settings')
          .select('setting_value')
          .eq('setting_key', 'default_refund_period_days')
          .maybeSingle();
      final raw = row?['setting_value'] as String?;
      if (raw != null) {
        final days = int.tryParse(raw);
        if (days != null && days >= 0) return days;
      }
    } catch (_) {}
    return 30; // hard-coded default matches kSettingDefaults
  }

  // ── Fetch bookings eligible for refund ────────────────────────────────────
  // Returns the authenticated customer's completed or cancelled bookings that
  // do not already have an active (non-terminal) refund request.

  Future<List<BookingForRefundModel>> fetchBookingsForRefund() async {
    try {
      // Resolve customer identity the same way BookingsService does.
      final customerId = await _getCustomerId();
      debugPrint('[Refund] fetchBookingsForRefund customer=$customerId');

      final data = await _client
          .from('bookings')
          .select(_bookingForRefundSelect)
          .eq('customer_id', customerId)
          .inFilter('status', ['completed', 'cancelled'])
          .order('service_date', ascending: false);

      debugPrint(
          '[Refund] fetchBookingsForRefund raw rows: ${(data as List).length}');

      var rows = (data as List<dynamic>)
          .map((r) =>
              BookingForRefundModel.fromMap(r as Map<String, dynamic>))
          .toList();

      // Exclude warranty rework bookings.
      // A booking is a rework if service_warranties.rework_booking_id = booking.id.
      // The server RPC also enforces this, but we filter here to keep them out
      // of the selection UI entirely.
      try {
        final bookingIds = rows.map((b) => b.id).toList();
        if (bookingIds.isNotEmpty) {
          final reworkRows = await _client
              .from('service_warranties')
              .select('rework_booking_id')
              .inFilter('rework_booking_id', bookingIds);

          final reworkBookingIds = (reworkRows as List<dynamic>)
              .map((r) =>
                  (r as Map<String, dynamic>)['rework_booking_id'] as String?)
              .whereType<String>()
              .toSet();

          if (reworkBookingIds.isNotEmpty) {
            rows = rows
                .where((b) => !reworkBookingIds.contains(b.id))
                .toList();
            debugPrint(
                '[Refund] fetchBookingsForRefund after rework exclusion: '
                '${rows.length} (removed ${reworkBookingIds.length})');
          }
        }
      } catch (e) {
        debugPrint(
            '[Refund] fetchBookingsForRefund: rework exclusion query '
            'failed: $e');
        // Proceed with unfiltered list — server RPC blocks rework submissions.
      }

      // Cancelled + Online but payment was never captured: nothing to refund.
      // Only online bookings with payment_status = 'success' (Razorpay captured)
      // are eligible for a cancellation refund. COD cancellations are kept in
      // the list but shown as disabled ("COD — No Refund Required").
      rows = rows
          .where((b) => !(b.status == 'cancelled' &&
              b.isOnlinePayment &&
              b.paymentStatus != 'success'))
          .toList();

      // Determine which bookings have active (non-terminal) tickets or a
      // completed refund transaction.
      //   • Active ticket  → exclude from list entirely (can't submit another).
      //   • Completed txn  → keep in list but mark as disabled ("Refund Already
      //                       Processed"). Backend RPC also enforces this.
      //   • Rejected / closed-without-completion → shown as selectable.
      try {
        final existingRequests = await _client
            .from('refund_requests')
            .select('id, booking_id, status')
            .eq('customer_id', customerId) as List<dynamic>;

        // Bookings with any non-terminal ticket are excluded from selection.
        final activeBookingIds = existingRequests
            .where((r) {
              final s = (r as Map<String, dynamic>)['status'] as String;
              return s != 'rejected' && s != 'closed';
            })
            .map((r) => (r as Map<String, dynamic>)['booking_id'] as String)
            .toSet();

        // Check for completed refund transactions on these requests.
        Set<String> completedRefundBookingIds = {};
        final requestIds = existingRequests
            .map((r) => (r as Map<String, dynamic>)['id'] as String)
            .toList();
        if (requestIds.isNotEmpty) {
          try {
            final txnRows = await _client
                .from('refund_transactions')
                .select('refund_request_id')
                .inFilter('refund_request_id', requestIds)
                .eq('status', 'completed') as List<dynamic>;

            final completedRequestIds = txnRows
                .map((r) =>
                    (r as Map<String, dynamic>)['refund_request_id'] as String)
                .toSet();

            final requestToBooking = Map.fromEntries(
              existingRequests.map((r) {
                final m = r as Map<String, dynamic>;
                return MapEntry(
                    m['id'] as String, m['booking_id'] as String);
              }),
            );

            completedRefundBookingIds = completedRequestIds
                .map((id) => requestToBooking[id])
                .whereType<String>()
                .toSet();
          } catch (e) {
            debugPrint(
                '[Refund] fetchBookingsForRefund: completed txn check '
                'failed: $e');
          }
        }

        // Fetch global refund period to compute eligibility deadlines.
        final refundPeriodDays = await fetchGlobalRefundPeriodDays();

        final result = rows
            .where((b) => !activeBookingIds.contains(b.id))
            .map((b) {
          if (completedRefundBookingIds.contains(b.id)) {
            return b.copyWith(hasCompletedRefund: true);
          }
          return b;
        }).toList();

        debugPrint(
            '[Refund] fetchBookingsForRefund after exclusion: ${result.length} '
            '(${completedRefundBookingIds.length} with completed refund, '
            'period=${refundPeriodDays}d)');

        // Attach the global period so callers can compute expiry.
        _lastFetchedRefundPeriodDays = refundPeriodDays;

        return result;
      } catch (e) {
        debugPrint(
            '[Refund] fetchBookingsForRefund: refund_requests exclusion '
            'query failed (policy not yet applied?): $e');
        return rows;
      }
    } catch (e, st) {
      debugPrint('[Refund] fetchBookingsForRefund error: $e\n$st');
      rethrow;
    }
  }

  // ── Create refund request ─────────────────────────────────────────────────

  Future<Map<String, String>> createRefundRequest({
    required String bookingId,
    required String issueCategoryId,
    required String description,
    required double requestedAmount,
    List<String> evidenceUrls = const [],
  }) async {
    final customerId = await _getCustomerId();
    final result = await _client.rpc(
      'customer_create_refund_request',
      params: {
        'p_booking_id': bookingId,
        'p_issue_category_id': issueCategoryId,
        'p_description': description,
        'p_requested_amount': requestedAmount,
        'p_evidence_urls': evidenceUrls,
        'p_customer_id': customerId,
      },
    );

    final map = result as Map<String, dynamic>;
    return {
      'id': map['id'] as String,
      'ticket_number': map['ticket_number'] as String,
    };
  }

  // ── Upload an image attachment to private storage ────────────────────────
  // Returns the storage path on success. Validates type and size client-side
  // before upload so failures are caught early without an RPC call.

  static const _allowedMimeTypes = {
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
  };
  static const int maxBytes = 5 * 1024 * 1024; // 5 MB (public for pre-validation)
  static const _maxBytes = maxBytes;

  Future<String> uploadMessageAttachment({
    required String refundRequestId,
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    final lowerMime = mimeType.toLowerCase();
    if (!_allowedMimeTypes.contains(lowerMime)) {
      throw Exception(
          'Unsupported file type. Only JPG, PNG, and WEBP are allowed.');
    }
    if (bytes.length > _maxBytes) {
      final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      throw Exception('File is ${mb}MB — maximum size is 5 MB.');
    }

    final customerId = await _getCustomerId();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeFilename =
        filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path = '$refundRequestId/cust_$customerId/${ts}_$safeFilename';

    await _client.storage
        .from('refund-message-attachments')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: lowerMime, upsert: false),
        );
    return path;
  }

  // ── Submit bank/UPI details for COD refund ───────────────────────────────

  Future<void> submitBankUpiDetails(
    String requestId,
    Map<String, dynamic> details,
  ) async {
    final customerId = await _getCustomerId();
    await _client.rpc(
      'customer_submit_bank_upi_details',
      params: {
        'p_request_id': requestId,
        'p_details': details,
        'p_customer_id': customerId,
      },
    );
  }

  // ── Add message to ticket ─────────────────────────────────────────────────

  Future<void> addMessage(
    String requestId,
    String message, {
    List<String> attachmentPaths = const [],
  }) async {
    final customerId = await _getCustomerId();
    await _client.rpc(
      'customer_add_refund_message',
      params: {
        'p_request_id': requestId,
        'p_message': message,
        'p_customer_id': customerId,
        'p_attachment_urls': attachmentPaths,
      },
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<List<RefundStatusEventModel>> _fetchStatusHistory(
      String requestId) async {
    final data = await _client
        .from('refund_status_history')
        .select(
          'id, refund_request_id, from_status, to_status, '
          'changed_by_type, notes, created_at',
        )
        .eq('refund_request_id', requestId)
        .order('created_at', ascending: true);

    return (data as List<dynamic>)
        .map((r) =>
            RefundStatusEventModel.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<RefundTransactionModel>> _fetchTransactions(
      String requestId) async {
    final data = await _client
        .from('refund_transactions')
        .select(
          'id, refund_request_id, amount, gateway, gateway_refund_id, '
          'status, failure_reason, refund_method, created_at, completed_at',
        )
        .eq('refund_request_id', requestId)
        .order('created_at', ascending: false);

    return (data as List<dynamic>)
        .map((r) =>
            RefundTransactionModel.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<RefundMessageModel>> _fetchMessages(
      String requestId) async {
    final data = await _client
        .from('refund_messages')
        .select(
          'id, refund_request_id, sender_type, sender_id, '
          'message, attachment_url, attachment_urls, is_internal, created_at',
        )
        .eq('refund_request_id', requestId)
        .eq('is_internal', false)
        .order('created_at', ascending: true);

    return (data as List<dynamic>)
        .map((r) =>
            RefundMessageModel.fromMap(r as Map<String, dynamic>))
        .toList();
  }
}
