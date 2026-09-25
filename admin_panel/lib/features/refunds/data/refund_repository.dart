import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/refund_request.dart';
import '../domain/models/refund_transaction.dart';
import '../domain/models/refund_status_event.dart';
import '../domain/models/refund_issue_category.dart';
import '../domain/models/refund_message.dart';

class RefundRepository {
  final SupabaseClient _supabase;

  const RefundRepository(this._supabase);

  // ── Fetch list ────────────────────────────────────────────────────────────

  Future<List<RefundRequest>> fetchRefundRequests({
    String? statusFilter,
    String? search,
    int limit = 100,
    int offset = 0,
  }) async {
    var filterBuilder = _supabase
        .from('refund_requests')
        .select(
          'id, ticket_number, booking_id, customer_id, payment_id, '
          'issue_category_id, description, requested_amount, evidence_urls, '
          'evidence_count, payment_method_snapshot, amount_paid_snapshot, '
          'status, approved_amount, admin_notes, decision_notes, '
          'reviewed_by, reviewed_at, processed_amount, '
          'closed_at, closed_by, created_at, updated_at, '
          'bank_details_requested_at, bank_details_submitted_at, '
          'bookings(booking_number), '
          'customers(full_name, phone), '
          'refund_issue_categories(label)',
        );

    if (statusFilter == 'awaiting_refund') {
      filterBuilder = filterBuilder
          .inFilter('status', ['approved', 'partially_approved']);
    } else if (statusFilter != null && statusFilter != 'all') {
      filterBuilder = filterBuilder.eq('status', statusFilter);
    }

    final data = await filterBuilder
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    var results = (data as List<dynamic>)
        .map((r) => RefundRequest.fromMap(r as Map<String, dynamic>))
        .toList();

    if (search != null && search.isNotEmpty) {
      final q = search.toLowerCase();
      results = results.where((r) {
        return r.ticketNumber.toLowerCase().contains(q) ||
            (r.bookingNumber?.toLowerCase().contains(q) ?? false) ||
            (r.customerName?.toLowerCase().contains(q) ?? false) ||
            (r.customerPhone?.contains(q) ?? false);
      }).toList();
    }

    return results;
  }

  // ── Fetch single with related data ────────────────────────────────────────

  Future<RefundRequest?> fetchRefundRequestById(String id) async {
    final data = await _supabase
        .from('refund_requests')
        .select(
          'id, ticket_number, booking_id, customer_id, payment_id, '
          'issue_category_id, description, requested_amount, evidence_urls, '
          'evidence_count, payment_method_snapshot, amount_paid_snapshot, '
          'status, approved_amount, admin_notes, decision_notes, '
          'reviewed_by, reviewed_at, processed_amount, '
          'closed_at, closed_by, created_at, updated_at, '
          'bank_details_requested_at, bank_details_submitted_at, bank_upi_details, '
          'bookings(booking_number, status, service_date, total_amount), '
          'customers(full_name, phone, email), '
          'refund_issue_categories(label, key)',
        )
        .eq('id', id)
        .maybeSingle();

    if (data == null) return null;
    final request = RefundRequest.fromMap(data);

    final txns = await fetchTransactions(id);
    final history = await fetchStatusHistory(id);

    return request.copyWith(transactions: txns, statusHistory: history);
  }

  // ── Transactions ──────────────────────────────────────────────────────────

  Future<List<RefundTransaction>> fetchTransactions(
      String refundRequestId) async {
    final data = await _supabase
        .from('refund_transactions')
        .select(
          'id, refund_request_id, amount, gateway, gateway_refund_id, '
          'status, failure_reason, refund_method, initiated_by, initiated_at, '
          'completed_at, metadata, created_at, updated_at',
        )
        .eq('refund_request_id', refundRequestId)
        .order('created_at', ascending: false);

    return (data as List<dynamic>)
        .map((r) => RefundTransaction.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  // ── Status history ────────────────────────────────────────────────────────

  Future<List<RefundStatusEvent>> fetchStatusHistory(
      String refundRequestId) async {
    final data = await _supabase
        .from('refund_status_history')
        .select()
        .eq('refund_request_id', refundRequestId)
        .order('created_at', ascending: true);

    return (data as List<dynamic>)
        .map((r) => RefundStatusEvent.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  // ── Issue categories ──────────────────────────────────────────────────────

  Future<List<RefundIssueCategory>> fetchIssueCategories() async {
    final data = await _supabase
        .from('refund_issue_categories')
        .select()
        .eq('is_active', true)
        .order('sort_order');

    return (data as List<dynamic>)
        .map((r) => RefundIssueCategory.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  // ── Create ticket (admin on behalf of customer) ───────────────────────────

  Future<RefundRequest> createRefundTicket({
    required String bookingId,
    required String customerId,
    String? paymentId,
    String? issueCategoryId,
    String? description,
    required double requestedAmount,
    required String paymentMethodSnapshot,
    required double amountPaidSnapshot,
    List<String> evidenceUrls = const [],
  }) async {
    final payload = {
      'ticket_number': '',
      'booking_id': bookingId,
      'customer_id': customerId,
      if (paymentId != null) 'payment_id': paymentId,
      if (issueCategoryId != null) 'issue_category_id': issueCategoryId,
      if (description != null) 'description': description,
      'requested_amount': requestedAmount,
      'payment_method_snapshot': paymentMethodSnapshot,
      'amount_paid_snapshot': amountPaidSnapshot,
      'evidence_urls': evidenceUrls,
      'evidence_count': evidenceUrls.length,
    };

    final data = await _supabase
        .from('refund_requests')
        .insert(payload)
        .select(
          'id, ticket_number, booking_id, customer_id, payment_id, '
          'issue_category_id, description, requested_amount, evidence_urls, '
          'evidence_count, payment_method_snapshot, amount_paid_snapshot, '
          'status, approved_amount, admin_notes, decision_notes, '
          'reviewed_by, reviewed_at, processed_amount, '
          'closed_at, closed_by, created_at, updated_at',
        )
        .single();

    return RefundRequest.fromMap(data);
  }

  // ── Admin review actions (via RPCs) ───────────────────────────────────────

  Future<void> markUnderReview(String requestId) async {
    await _supabase.rpc(
      'admin_mark_refund_under_review',
      params: {'p_request_id': requestId},
    );
  }

  Future<void> requestMoreInfo(String requestId, String message) async {
    await _supabase.rpc(
      'admin_request_more_info_refund',
      params: {
        'p_request_id': requestId,
        'p_message': message,
      },
    );
  }

  Future<void> approveRequest(
    String requestId, {
    required double approvedAmount,
    String? notes,
  }) async {
    await _supabase.rpc(
      'admin_approve_refund_request',
      params: {
        'p_request_id': requestId,
        'p_approved_amount': approvedAmount,
        if (notes != null) 'p_notes': notes,
      },
    );
  }

  Future<void> rejectRequest(String requestId, {required String reason}) async {
    await _supabase.rpc(
      'admin_reject_refund_request',
      params: {
        'p_request_id': requestId,
        'p_reason': reason,
      },
    );
  }

  Future<void> requestCodBankDetails(String requestId) async {
    await _supabase.rpc(
      'admin_request_cod_bank_details',
      params: {'p_request_id': requestId},
    );
  }

  Future<void> initiateCodRefund(String requestId) async {
    await _supabase.rpc(
      'admin_initiate_cod_refund',
      params: {'p_request_id': requestId},
    );
  }

  Future<void> closeRequest(String requestId, {String? notes}) async {
    await _supabase.rpc(
      'admin_close_refund_request',
      params: {
        'p_request_id': requestId,
        if (notes != null) 'p_notes': notes,
      },
    );
  }

  // ── Financial safety (via RPCs) ───────────────────────────────────────────

  Future<double> getRefundableBalance(String requestId) async {
    final result = await _supabase.rpc(
      'get_refundable_balance',
      params: {'p_request_id': requestId},
    );
    return (result as num).toDouble();
  }

  Future<String> initiateRefundTransaction({
    required String requestId,
    required double amount,
    required String gateway,
    required String refundMethod,
    String? notes,
  }) async {
    final result = await _supabase.rpc(
      'admin_initiate_refund_transaction',
      params: {
        'p_request_id': requestId,
        'p_amount': amount,
        'p_gateway': gateway,
        'p_refund_method': refundMethod,
        if (notes != null) 'p_notes': notes,
      },
    );
    return result as String;
  }

  Future<void> markTransactionComplete(
    String transactionId, {
    String? gatewayRefundId,
  }) async {
    await _supabase.rpc(
      'admin_mark_refund_transaction_complete',
      params: {
        'p_transaction_id': transactionId,
        if (gatewayRefundId != null) 'p_gateway_refund_id': gatewayRefundId,
      },
    );
  }

  Future<void> markTransactionFailed(
    String transactionId, {
    required String failureReason,
  }) async {
    await _supabase.rpc(
      'admin_mark_refund_transaction_failed',
      params: {
        'p_transaction_id': transactionId,
        'p_failure_reason': failureReason,
      },
    );
  }

  // ── Razorpay refund processing ────────────────────────────────────────────
  //
  // Calls the process-razorpay-refund Edge Function, which:
  //   1. Verifies the caller is an active admin (via RPC + auth.uid()).
  //   2. Atomically locks the transaction and transitions pending → processing.
  //   3. Calls the Razorpay Refunds API with an idempotency key.
  //   4. On status=processed: marks transaction complete (via RPC), returns 200.
  //   5. On status=pending: stores gateway_refund_id, returns 202 pending=true.
  //   6. On definitive failure: marks transaction failed (via RPC), throws.
  //   7. On uncertain outcome: returns 202 (transaction stays processing).
  //
  // Returns 'confirmed' — Razorpay immediately settled the refund (HTTP 200).
  // Returns 'pending'   — Razorpay queued it; webhook will finalise (HTTP 202 pending=true).
  // Returns 'uncertain' — Outcome unclear (HTTP 202, other) — check dashboard.
  // Throws on validation errors (400/409), auth failure (403), or gateway errors (422/500).

  Future<String> processRazorpayRefund(String transactionId) async {
    final response = await _supabase.functions.invoke(
      'process-razorpay-refund',
      body: {'transaction_id': transactionId},
    );
    final status = response.status;
    if (status >= 400) {
      final data = response.data;
      final msg = data is Map ? data['error'] as String? : null;
      throw Exception(msg ?? 'Refund processing failed (HTTP $status)');
    }
    if (status == 200) return 'confirmed';
    final data = response.data;
    if (data is Map && data['pending'] == true) return 'pending';
    return 'uncertain';
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  Future<List<RefundMessage>> fetchMessages(String refundRequestId) async {
    final data = await _supabase
        .from('refund_messages')
        .select(
          'id, refund_request_id, sender_type, sender_id, '
          'message, attachment_url, attachment_urls, is_internal, created_at',
        )
        .eq('refund_request_id', refundRequestId)
        .order('created_at', ascending: true);

    return (data as List<dynamic>)
        .map((r) => RefundMessage.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  // Generates a signed URL for a storage path in the refund-message-attachments bucket.
  // Returns null on any failure so callers can degrade gracefully.
  Future<String?> getSignedAttachmentUrl(String storagePath) async {
    try {
      return await _supabase.storage
          .from('refund-message-attachments')
          .createSignedUrl(storagePath, 3600);
    } catch (e) {
      debugPrint('[Refund] getSignedAttachmentUrl failed for $storagePath: $e');
      return null;
    }
  }

  // Uploads image bytes to the refund-message-attachments private bucket.
  // Returns the storage path (not the URL) on success.
  Future<String> uploadMessageAttachment({
    required String refundRequestId,
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    _validateAttachment(bytes, mimeType);
    final adminUserId = _supabase.auth.currentUser?.id ?? 'unknown';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeFilename = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path = '$refundRequestId/admin_$adminUserId/${ts}_$safeFilename';
    await _supabase.storage
        .from('refund-message-attachments')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    return path;
  }

  // Sends a message from the admin on a refund ticket.
  // Uses direct INSERT since the admin_all_refund_messages policy allows it.
  Future<void> sendAdminMessage({
    required String requestId,
    required String message,
    List<String> attachmentPaths = const [],
    bool isInternal = false,
  }) async {
    final adminUserId = _supabase.auth.currentUser?.id;
    await _supabase.from('refund_messages').insert({
      'refund_request_id': requestId,
      'sender_type': 'admin',
      'sender_id': adminUserId,
      'message': message.trim(),
      'attachment_urls': attachmentPaths,
      'is_internal': isInternal,
    });
  }

  // ── Add internal admin note ───────────────────────────────────────────────

  Future<void> addInternalNote({
    required String requestId,
    required String message,
    required String adminUserId,
  }) async {
    await _supabase.from('refund_messages').insert({
      'refund_request_id': requestId,
      'sender_type': 'admin',
      'sender_id': adminUserId,
      'message': message,
      'is_internal': true,
    });
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  static const _allowedMimeTypes = {
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
  };
  static const _maxBytes = 5 * 1024 * 1024; // 5 MB

  void _validateAttachment(Uint8List bytes, String mimeType) {
    if (!_allowedMimeTypes.contains(mimeType.toLowerCase())) {
      throw Exception(
          'Unsupported file type "$mimeType". Only JPG, PNG, and WEBP are allowed.');
    }
    if (bytes.length > _maxBytes) {
      final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      throw Exception('File is ${mb}MB — maximum size is 5 MB.');
    }
  }

  // ── Lookup: payment context for a booking ────────────────────────────────
  // Used when admin creates a ticket: auto-populates payment context.
  // Handles legacy 'razorpay' payment_method identically to 'online'.

  Future<Map<String, dynamic>?> fetchBookingPaymentContext(
      String bookingId) async {
    final booking = await _supabase
        .from('bookings')
        .select(
          'id, booking_number, status, payment_method, payment_status, '
          'total_amount, service_date, customer_id, '
          'customers(full_name, phone)',
        )
        .eq('id', bookingId)
        .maybeSingle();

    if (booking == null) return null;

    final paymentMethod = booking['payment_method'] as String? ?? 'cash';
    double amountPaid = (booking['total_amount'] as num?)?.toDouble() ?? 0.0;
    String? paymentId;

    if (paymentMethod == 'online' || paymentMethod == 'razorpay') {
      final payment = await _supabase
          .from('booking_payments')
          .select('id, amount, status')
          .eq('booking_id', bookingId)
          .eq('status', 'success')
          .order('attempt_number', ascending: false)
          .limit(1)
          .maybeSingle();

      if (payment != null) {
        paymentId = payment['id'] as String;
        amountPaid = (payment['amount'] as num).toDouble();
      }
    }

    String snapshot;
    if (paymentMethod == 'online' || paymentMethod == 'razorpay') {
      snapshot = 'online';
    } else if (paymentMethod == 'cod') {
      snapshot = 'cod';
    } else {
      snapshot = 'cash';
    }

    return {
      'booking': booking,
      'payment_id': paymentId,
      'payment_method_snapshot': snapshot,
      'amount_paid_snapshot': amountPaid,
    };
  }

  // ── Search bookings for the create-ticket dialog ──────────────────────────
  // Two-path search handles both cases:
  //   A. Bookings with a real booking_number value (new or after backfill):
  //      matched via booking_number ILIKE '%query%'.
  //   Both strategies (booking_number ILIKE and id::TEXT ILIKE) run inside the
  //   admin_search_bookings_by_ref RPC, which avoids the PostgREST limitation
  //   where the Dart client drops the ::text cast, causing "operator does not
  //   exist: uuid ~~ unknown" at runtime.  The RPC returns matching IDs; full
  //   booking details are fetched in a second query using inFilter.

  Future<List<Map<String, dynamic>>> searchBookingsForRefund(
      String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    // Step 1: get matching booking IDs from the RPC (handles BK- stripping and
    // the id::TEXT cast server-side where it works correctly).
    final idRows = await _supabase.rpc(
      'admin_search_bookings_by_ref',
      params: {'p_query': trimmed},
    ) as List<dynamic>;

    if (idRows.isEmpty) return [];

    final ids = idRows.map((r) => (r as Map<String, dynamic>)['id'] as String).toList();

    // Step 2: fetch full booking details for the matched IDs.
    const cols = 'id, booking_number, status, payment_method, payment_status, '
        'total_amount, service_date, created_at, customer_id, '
        'customers(full_name, phone)';

    final rows = await _supabase
        .from('bookings')
        .select(cols)
        .inFilter('id', ids)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows as List<dynamic>);
  }

  // ── Admin create refund request (via RPC) ─────────────────────────────────
  // Calls admin_create_refund_request which enforces admin auth, booking
  // ownership, rework check, duplicate prevention, and payment routing.
  // Returns the new ticket's id and ticket_number on success.

  Future<Map<String, dynamic>> adminCreateRefundRequest({
    required String bookingId,
    required String customerId,
    required String issueCategoryId,
    String? description,
    required double requestedAmount,
    String? notes,
  }) async {
    final result = await _supabase.rpc(
      'admin_create_refund_request',
      params: {
        'p_booking_id': bookingId,
        'p_customer_id': customerId,
        'p_issue_category_id': issueCategoryId,
        'p_description': description ?? '',
        'p_requested_amount': requestedAmount,
        if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
      },
    );
    return result as Map<String, dynamic>;
  }

  // ── Check for existing active tickets on a booking ────────────────────────

  Future<bool> hasActiveRefundTicket(String bookingId) async {
    final data = await _supabase
        .from('refund_requests')
        .select('id')
        .eq('booking_id', bookingId)
        .not('status', 'in', '("rejected","closed")')
        .limit(1);
    return (data as List).isNotEmpty;
  }
}
