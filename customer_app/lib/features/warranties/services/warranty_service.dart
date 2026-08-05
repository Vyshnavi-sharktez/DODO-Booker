import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/service_warranty_model.dart';

class WarrantyService {
  static const _phoneKey = 'dodo_auth_phone';
  final _client = Supabase.instance.client;

  Future<String?> _getCustomerId() async {
    try {
      final user = _client.auth.currentUser;
      if (user != null) return user.id;

      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString(_phoneKey);
      if (phone != null && phone.isNotEmpty) {
        final row = await _client
            .from('customers')
            .select('id')
            .eq('phone', phone)
            .maybeSingle();
        if (row != null && row['id'] != null) {
          return row['id'] as String;
        }
      }
      return null;
    } catch (e) {
      debugPrint('[DODO][WarrantyService] Error resolving customerId: $e');
      return null;
    }
  }

  /// Fetch service warranty for a specific booking by bookingId
  Future<ServiceWarrantyModel?> fetchWarrantyByBookingId(String bookingId) async {
    try {
      final data = await _client
          .from('service_warranties')
          .select('''
            *,
            bookings!booking_id(booking_number, notes, vendors(business_name)),
            rework_booking:bookings!rework_booking_id(id, booking_number, notes, status, dispatch_status, vendor_id, created_at, updated_at, completed_at, vendors(business_name)),
            vendors(business_name)
          ''')
          .or('booking_id.eq.$bookingId,rework_booking_id.eq.$bookingId')
          .maybeSingle();

      if (data == null) return null;
      final model = ServiceWarrantyModel.fromJson(Map<String, dynamic>.from(data));
      await _syncCompletedReworkWarranties([model]);
      if (model.reworkStatus?.toLowerCase() == 'completed' && model.status.toLowerCase() != 'resolved') {
        return ServiceWarrantyModel.fromJson({
          ...data,
          'status': 'Resolved',
        });
      }
      return model;
    } catch (e) {
      debugPrint('[DODO][WarrantyService] Primary fetch failed for booking $bookingId: $e');
      try {
        final fallback = await _client
            .from('service_warranties')
            .select('*')
            .or('booking_id.eq.$bookingId,rework_booking_id.eq.$bookingId')
            .maybeSingle();
        if (fallback == null) return null;
        return ServiceWarrantyModel.fromJson(Map<String, dynamic>.from(fallback));
      } catch (e2) {
        debugPrint('[DODO][WarrantyService] Fallback fetch failed: $e2');
        return null;
      }
    }
  }

  /// Fetch all warranties for the current customer
  Future<List<ServiceWarrantyModel>> fetchCustomerWarranties() async {
    try {
      final customerId = await _getCustomerId();
      if (customerId == null || customerId.isEmpty) {
        debugPrint('[DODO][WarrantyService] fetchCustomerWarranties → customerId is null/empty');
        return [];
      }

      debugPrint('[DODO][WarrantyService] Querying service_warranties for customer_id=$customerId');

      final data = await _client
          .from('service_warranties')
          .select('''
            *,
            bookings!booking_id(booking_number, notes, vendors(business_name)),
            rework_booking:bookings!rework_booking_id(id, booking_number, notes, status, dispatch_status, vendor_id, created_at, updated_at, completed_at, vendors(business_name)),
            vendors(business_name)
          ''')
          .eq('customer_id', customerId)
          .order('issued_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(data as List);
      final models = list.map(ServiceWarrantyModel.fromJson).toList();
      await _syncCompletedReworkWarranties(models);
      return models;
    } catch (e) {
      debugPrint('[DODO][WarrantyService] Primary fetch customer warranties failed: $e');
      try {
        final customerId = await _getCustomerId();
        if (customerId == null) return [];
        final fallback = await _client
            .from('service_warranties')
            .select('*')
            .eq('customer_id', customerId)
            .order('issued_at', ascending: false);
        final list = List<Map<String, dynamic>>.from(fallback as List);
        return list.map(ServiceWarrantyModel.fromJson).toList();
      } catch (e2) {
        debugPrint('[DODO][WarrantyService] Fallback customer warranties failed: $e2');
        return [];
      }
    }
  }

  Future<void> _syncCompletedReworkWarranties(List<ServiceWarrantyModel> list) async {
    for (final w in list) {
      if (w.reworkStatus?.toLowerCase() == 'completed' && w.status.toLowerCase() != 'resolved') {
        try {
          final nowIso = DateTime.now().toIso8601String();
          await _client.from('service_warranties').update({
            'status': 'Resolved',
            'updated_at': nowIso,
          }).eq('id', w.id);
          debugPrint('[DODO][WarrantyService] Auto-synced completed rework warranty ${w.id} to Resolved in DB');
        } catch (e) {
          debugPrint('[DODO][WarrantyService] Warning: Auto-sync failed for warranty ${w.id}: $e');
        }
      }
    }
  }

  /// Fetch grouped rework images (evidence, before, after)
  Future<Map<String, List<String>>> fetchGroupedReworkImages(String reworkBookingId) async {
    final result = <String, List<String>>{
      'evidence': [],
      'before': [],
      'after': [],
    };
    if (reworkBookingId.isEmpty) return result;

    try {
      final res = await _client
          .from('booking_images')
          .select('image_url, image_type')
          .eq('booking_id', reworkBookingId);

      final list = List<Map<String, dynamic>>.from(res as List);
      for (final row in list) {
        final url = row['image_url'] as String?;
        final type = (row['image_type'] as String? ?? '').toLowerCase();

        if (url == null || url.isEmpty) continue;

        if (type == 'warranty_claim_evidence' || type.contains('evidence')) {
          result['evidence']!.add(url);
        } else if (type == 'before' || type.contains('before')) {
          result['before']!.add(url);
        } else if (type == 'after' || type.contains('after')) {
          result['after']!.add(url);
        } else {
          result['evidence']!.add(url);
        }
      }
    } catch (e) {
      debugPrint('[DODO][WarrantyService] Error fetching rework images: $e');
    }
    return result;
  }

  /// Submit a warranty claim:
  /// 1. Validates status & active window (prevents duplicates & expired claims).
  /// 2. Creates a 0-cost linked rework booking in `bookings` table.
  /// 3. Copies itemization to `booking_items` and photo evidence to `booking_images`.
  /// 4. Updates `service_warranties`: status='Claimed', claimed_at=now(), rework_booking_id.
  /// 5. Sends notifications to Admin, Vendor, and Customer.
  Future<String> submitWarrantyClaim({
    required String warrantyId,
    required String bookingId,
    required String customerId,
    String? vendorId,
    required String issueDescription,
    required List<String> photoUrls,
    DateTime? preferredDate,
  }) async {
    final desc = issueDescription.trim();
    if (desc.isEmpty) {
      throw Exception('Issue description is mandatory.');
    }
    if (photoUrls.length < 2) {
      throw Exception('Minimum 2 evidence photos are required to claim warranty.');
    }

    // 1. Verify warranty status & expiry
    final warrantyRow = await _client
        .from('service_warranties')
        .select('*')
        .eq('id', warrantyId)
        .maybeSingle();

    if (warrantyRow == null) {
      throw Exception('Warranty record not found.');
    }

    final currentStatus = (warrantyRow['status'] as String? ?? '').toLowerCase();
    final expiresAt = DateTime.tryParse(warrantyRow['expires_at'] as String? ?? '') ?? DateTime.now();

    if (currentStatus == 'claimed') {
      throw Exception('This warranty has already been claimed.');
    }

    if (currentStatus == 'expired' || expiresAt.isBefore(DateTime.now())) {
      throw Exception('Warranty period has expired. Claims must be submitted before expiry.');
    }

    // 2. Fetch original booking details
    final origBookingRow = await _client
        .from('bookings')
        .select('*')
        .eq('id', bookingId)
        .single();

    final origBookingMap = Map<String, dynamic>.from(origBookingRow);
    final origBookingNum = origBookingMap['booking_number'] as String? ?? bookingId;

    final serviceDateStr = (preferredDate ?? DateTime.now().add(const Duration(days: 1)))
        .toIso8601String()
        .split('T')
        .first;

    // 3. Create Rework Booking
    // Try inserting with pre-assigned vendor_id first. If vendor assignment fails
    // (e.g. wallet threshold constraint, inactive vendor), fallback to unassigned rework booking.
    Map<String, dynamic>? reworkBookingData;
    String? assignedVendorId = vendorId;

    final basePayload = <String, dynamic>{
      'customer_id': customerId,
      'status': 'pending',
      'subtotal': 0.0,
      'discount_amount': 0.0,
      'total_amount': 0.0,
      'service_date': serviceDateStr,
      'scheduled_time': origBookingMap['scheduled_time'] ?? '10:00 AM',
      'address': origBookingMap['address'],
      'latitude': origBookingMap['latitude'],
      'longitude': origBookingMap['longitude'],
      'service_id': origBookingMap['service_id'],
      'notes': '[WARRANTY REWORK] Claim for Booking #$origBookingNum\nIssue: $desc',
      'payment_method': origBookingMap['payment_method'] ?? 'cash',
      'payment_status': 'completed',
    };

    if (assignedVendorId != null && assignedVendorId.isNotEmpty) {
      try {
        final payloadWithVendor = Map<String, dynamic>.from(basePayload)..addAll({
          'vendor_id': assignedVendorId,
          'assignment_type': 'External Vendor',
          'dispatch_status': 'assigned',
        });
        reworkBookingData = Map<String, dynamic>.from(
          await _client.from('bookings').insert(payloadWithVendor).select().single(),
        );
      } catch (e) {
        debugPrint('[WarrantyService] Pre-assigning vendor $assignedVendorId failed: $e. Falling back to unassigned rework booking.');
        assignedVendorId = null;
      }
    }

    if (reworkBookingData == null) {
      final unassignedPayload = Map<String, dynamic>.from(basePayload)..addAll({
        'vendor_id': null,
        'assignment_type': 'Unassigned',
        'dispatch_status': 'idle',
      });
      reworkBookingData = Map<String, dynamic>.from(
        await _client.from('bookings').insert(unassignedPayload).select().single(),
      );
    }

    final reworkBookingId = reworkBookingData['id'] as String;
    final reworkBookingNum = reworkBookingData['booking_number'] as String? ?? reworkBookingId;

    // 4. Duplicate original booking_items to rework booking
    final origItemsData = await _client
        .from('booking_items')
        .select('*')
        .eq('booking_id', bookingId);

    final origItemsList = List<Map<String, dynamic>>.from(origItemsData as List);
    if (origItemsList.isNotEmpty) {
      final reworkItemsPayload = origItemsList.map((item) => {
        'booking_id': reworkBookingId,
        'service_id': item['service_id'],
        'quantity': item['quantity'] ?? 1,
        'unit_price': 0.0,
        'total_price': 0.0,
      }).toList();

      try {
        await _client.from('booking_items').insert(reworkItemsPayload);
      } catch (e) {
        debugPrint('[WarrantyService] Warning: booking_items copy failed: $e');
      }
    }

    // 5. Insert evidence photos into booking_images
    final imageRows = photoUrls.map((url) => {
      'booking_id': reworkBookingId,
      'image_url': url,
      'image_type': 'warranty_claim_evidence',
    }).toList();

    try {
      await _client.from('booking_images').insert(imageRows);
    } catch (e) {
      debugPrint('[WarrantyService] Warning: booking_images insert failed: $e');
    }

    // 6. Update service_warranties table: status = 'Claimed'
    final nowIso = DateTime.now().toIso8601String();
    final updatePayload = <String, dynamic>{
      'status': 'Claimed',
      'claimed_at': nowIso,
      'rework_booking_id': reworkBookingId,
      'updated_at': nowIso,
    };

    final updatedRows = await _client
        .from('service_warranties')
        .update(updatePayload)
        .eq('id', warrantyId)
        .select();

    if ((updatedRows as List).isEmpty) {
      debugPrint('[WarrantyService] Warning: Update by id=$warrantyId returned 0 rows. Attempting update by booking_id=$bookingId');
      final fallbackRows = await _client
          .from('service_warranties')
          .update(updatePayload)
          .eq('booking_id', bookingId)
          .select();

      if ((fallbackRows as List).isEmpty) {
        throw Exception('Failed to update warranty claim status to Claimed.');
      }
    }

    // 7. Notifications
    // Admin notification
    try {
      await _client.from('notifications').insert({
        'user_type': 'admin',
        'user_id': null,
        'title': 'Warranty Claim Filed',
        'message': 'Warranty claim filed for Booking #$origBookingNum. Rework booking #$reworkBookingNum created.',
        'notification_type': 'warranty_claim',
        'is_read': false,
        'entity_type': 'service_warranty',
        'entity_id': warrantyId,
      });
    } catch (e) {
      debugPrint('[WarrantyService] Warning: admin notification failed: $e');
    }

    // Vendor notification (if vendor exists)
    if (vendorId != null && vendorId.isNotEmpty) {
      try {
        await _client.from('notifications').insert({
          'user_type': 'vendor',
          'user_id': vendorId,
          'title': 'Warranty Rework Booking Assigned',
          'message': 'A warranty rework booking (#$reworkBookingNum) has been assigned to you for original booking #$origBookingNum.',
          'notification_type': 'warranty_claim',
          'is_read': false,
          'entity_type': 'booking',
          'entity_id': reworkBookingId,
        });
      } catch (e) {
        debugPrint('[WarrantyService] Warning: vendor notification failed: $e');
      }
    }

    // Customer notification
    try {
      await _client.from('notifications').insert({
        'user_type': 'customer',
        'user_id': customerId,
        'title': 'Warranty Claim Submitted',
        'message': 'Your warranty claim for Booking #$origBookingNum has been approved. Rework booking #$reworkBookingNum has been created.',
        'notification_type': 'warranty_claim',
        'is_read': false,
        'entity_type': 'booking',
        'entity_id': reworkBookingId,
      });
    } catch (e) {
      debugPrint('[WarrantyService] Warning: customer notification failed: $e');
    }

    return reworkBookingId;
  }
}
