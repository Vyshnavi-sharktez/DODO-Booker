import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/service_warranty.dart';

class WarrantiesRepository {
  final SupabaseClient _client;

  WarrantiesRepository(this._client);

  /// Fetch ONLY submitted warranty claims (status IN ('Claimed', 'Approved', 'Resolved', 'Rejected') or claimed_at != null)
  Future<List<ServiceWarranty>> fetchWarrantyClaims() async {
    try {
      final response = await _client
          .from('service_warranties')
          .select('''
            *,
            bookings!booking_id(booking_number, notes, customers(full_name, email, phone)),
            rework_booking:bookings!rework_booking_id(id, booking_number, notes, status, dispatch_status, vendor_id, created_at, updated_at, completed_at, vendors(business_name)),
            vendors(business_name)
          ''')
          .or('claimed_at.not.is.null,rework_booking_id.not.is.null,status.eq.Claimed,status.eq.Approved,status.eq.Resolved,status.eq.Rejected')
          .order('claimed_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(response as List);
      final warranties = list.map(ServiceWarranty.fromMap).toList();

      for (final w in warranties) {
        if (w.status.toLowerCase() == 'approved' &&
            w.reworkStatus?.toLowerCase() == 'completed') {
          try {
            await _client.from('service_warranties').update({
              'status': 'Resolved',
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', w.id);
          } catch (_) {}
        }
      }

      return _populateMissingDetails(warranties);
    } catch (e, st) {
      debugPrint('[DODO][WarrantiesRepository] Primary fetchWarrantyClaims failed: $e');
      debugPrint(st.toString());

      try {
        // Fallback 1: Query without nested vendors inside rework_booking
        final rawResponse = await _client
            .from('service_warranties')
            .select('''
              *,
              bookings!booking_id(booking_number, notes, customers(full_name, email, phone)),
              rework_booking:bookings!rework_booking_id(id, booking_number, notes, status, dispatch_status, vendor_id, created_at, updated_at, completed_at),
              vendors(business_name)
            ''')
            .or('claimed_at.not.is.null,rework_booking_id.not.is.null,status.eq.Claimed,status.eq.Approved,status.eq.Resolved,status.eq.Rejected')
            .order('claimed_at', ascending: false);

        final rawList = List<Map<String, dynamic>>.from(rawResponse as List);
        final resList = rawList.map(ServiceWarranty.fromMap).toList();
        return _populateMissingDetails(resList);
      } catch (e2) {
        debugPrint('[DODO][WarrantiesRepository] Fallback 1 fetchWarrantyClaims failed: $e2');

        try {
          // Fallback 2: Basic select without complex filters, then filter in memory
          final baseResponse = await _client
              .from('service_warranties')
              .select('''
                *,
                bookings!booking_id(booking_number, notes),
                rework_booking:bookings!rework_booking_id(booking_number, notes, status)
              ''')
              .order('claimed_at', ascending: false);

          final baseList = List<Map<String, dynamic>>.from(baseResponse as List);
          final allWarranties = baseList.map(ServiceWarranty.fromMap).toList();
          final filtered = allWarranties.where((w) =>
            w.claimedAt != null ||
            w.reworkBookingId != null ||
            ['claimed', 'approved', 'resolved', 'rejected'].contains(w.status.toLowerCase())
          ).toList();
          return _populateMissingDetails(filtered);
        } catch (e3) {
          debugPrint('[DODO][WarrantiesRepository] Fallback 2 fetchWarrantyClaims failed: $e3');
          return [];
        }
      }
    }
  }

  /// Fetch ALL service warranties for analytics (Active, Claimed, Approved, Resolved, Rejected, Expired)
  Future<List<ServiceWarranty>> fetchAnalyticsWarranties() async {
    try {
      final response = await _client
          .from('service_warranties')
          .select('''
            *,
            bookings!booking_id(booking_number, notes, customers(full_name, email, phone)),
            rework_booking:bookings!rework_booking_id(id, booking_number, notes, status, dispatch_status, vendor_id, created_at, updated_at, completed_at, vendors(business_name)),
            vendors(business_name)
          ''')
          .order('issued_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(response as List);
      final warranties = list.map(ServiceWarranty.fromMap).toList();
      return _populateMissingDetails(warranties);
    } catch (e) {
      debugPrint('[DODO][WarrantiesRepository] Primary fetchAnalyticsWarranties failed: $e');
      try {
        final fallback = await _client
            .from('service_warranties')
            .select('*')
            .order('issued_at', ascending: false);
        final list = List<Map<String, dynamic>>.from(fallback as List);
        return list.map(ServiceWarranty.fromMap).toList();
      } catch (e2) {
        debugPrint('[DODO][WarrantiesRepository] Fallback fetchAnalyticsWarranties failed: $e2');
        return [];
      }
    }
  }

  Future<List<ServiceWarranty>> _populateMissingDetails(List<ServiceWarranty> list) async {
    if (list.isEmpty) return list;

    final missingVendorIds = <String>{};
    final missingCustomerIds = <String>{};

    for (final w in list) {
      if ((w.reworkVendorName == null || w.reworkVendorName!.isEmpty) && w.vendorId != null && w.vendorId!.isNotEmpty) {
        missingVendorIds.add(w.vendorId!);
      }
      if ((w.customerName == null || w.customerName!.isEmpty || w.customerName == 'Customer') && w.customerId.isNotEmpty) {
        missingCustomerIds.add(w.customerId);
      }
    }

    final vendorMap = <String, String>{};
    if (missingVendorIds.isNotEmpty) {
      try {
        final res = await _client
            .from('vendors')
            .select('id, business_name')
            .inFilter('id', missingVendorIds.toList());
        for (final row in res as List<dynamic>) {
          final m = row as Map<String, dynamic>;
          final id = m['id'] as String?;
          final name = m['business_name'] as String?;
          if (id != null && name != null) {
            vendorMap[id] = name;
          }
        }
      } catch (e) {
        debugPrint('[DODO][WarrantiesRepository] Warning: vendor lookup failed: $e');
      }
    }

    final customerMap = <String, Map<String, String>>{};
    if (missingCustomerIds.isNotEmpty) {
      try {
        final res = await _client
            .from('customers')
            .select('id, full_name, email, phone')
            .inFilter('id', missingCustomerIds.toList());
        for (final row in res as List<dynamic>) {
          final m = row as Map<String, dynamic>;
          final id = m['id'] as String?;
          if (id != null) {
            customerMap[id] = {
              'full_name': m['full_name'] as String? ?? '',
              'email': m['email'] as String? ?? '',
              'phone': m['phone'] as String? ?? '',
            };
          }
        }
      } catch (e) {
        debugPrint('[DODO][WarrantiesRepository] Warning: customer lookup failed: $e');
      }
    }

    if (vendorMap.isEmpty && customerMap.isEmpty) return list;

    return list.map((w) {
      var updated = w;
      if ((updated.reworkVendorName == null || updated.reworkVendorName!.isEmpty) && updated.vendorId != null && vendorMap.containsKey(updated.vendorId)) {
        final vName = vendorMap[updated.vendorId]!;
        updated = updated.copyWith(
          vendorName: updated.vendorName ?? vName,
          reworkVendorName: updated.reworkVendorName ?? vName,
        );
      }
      if ((updated.customerName == null || updated.customerName!.isEmpty || updated.customerName == 'Customer') && customerMap.containsKey(updated.customerId)) {
        final cInfo = customerMap[updated.customerId]!;
        updated = updated.copyWith(
          customerName: cInfo['full_name']!.isNotEmpty ? cInfo['full_name'] : updated.customerName,
          customerEmail: cInfo['email']!.isNotEmpty ? cInfo['email'] : updated.customerEmail,
          customerPhone: cInfo['phone']!.isNotEmpty ? cInfo['phone'] : updated.customerPhone,
        );
      }
      return updated;
    }).toList();
  }

  /// Fetch all warranty records
  Future<List<ServiceWarranty>> fetchWarranties() async {
    try {
      final response = await _client
          .from('service_warranties')
          .select('''
            *,
            bookings!booking_id(booking_number, notes, customers(full_name, email, phone)),
            rework_booking:bookings!rework_booking_id(id, booking_number, notes, status, dispatch_status, vendor_id, created_at, updated_at, completed_at, vendors(business_name)),
            vendors(business_name),
            customers!customer_id(full_name, email, phone)
          ''')
          .order('claimed_at', ascending: false, nullsFirst: false)
          .order('issued_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(response as List);
      return list.map(ServiceWarranty.fromMap).toList();
    } catch (e, st) {
      debugPrint('[DODO][WarrantiesRepository] Error joining customers/vendors, falling back to base fetch: $e');
      debugPrint(st.toString());

      try {
        final rawResponse = await _client
            .from('service_warranties')
            .select('''
              *,
              bookings!booking_id(booking_number, notes, customers(full_name, email, phone)),
              rework_booking:bookings!rework_booking_id(id, booking_number, notes, status, dispatch_status, vendor_id, created_at, updated_at, completed_at),
              vendors(business_name)
            ''')
            .order('issued_at', ascending: false);

        final rawList = List<Map<String, dynamic>>.from(rawResponse as List);
        return rawList.map(ServiceWarranty.fromMap).toList();
      } catch (e2) {
        debugPrint('[DODO][WarrantiesRepository] Error in fallback fetch: $e2');
        return [];
      }
    }
  }

  /// Fetch evidence photos associated with the warranty claim rework booking
  Future<List<String>> fetchEvidenceImages(String reworkBookingId) async {
    if (reworkBookingId.isEmpty) return [];
    try {
      final response = await _client
          .from('booking_images')
          .select('image_url')
          .eq('booking_id', reworkBookingId);

      final list = List<Map<String, dynamic>>.from(response as List);
      return list
          .map((row) => row['image_url'] as String?)
          .whereType<String>()
          .toList();
    } catch (e) {
      debugPrint('[DODO][WarrantiesRepository] Error fetching evidence images: $e');
      return [];
    }
  }

  /// Fetch categorized photos (evidence, before, after) associated with the rework booking
  Future<Map<String, List<String>>> fetchReworkImagesGrouped(String reworkBookingId) async {
    final result = <String, List<String>>{
      'evidence': [],
      'before': [],
      'after': [],
    };
    if (reworkBookingId.isEmpty) return result;

    try {
      final response = await _client
          .from('booking_images')
          .select('image_url, image_type')
          .eq('booking_id', reworkBookingId);

      final list = List<Map<String, dynamic>>.from(response as List);
      for (final row in list) {
        final url = row['image_url'] as String?;
        final type = (row['image_type'] as String? ?? '').toLowerCase();
        if (url == null || url.isEmpty) continue;

        if (type == 'warranty_claim_evidence' || type == 'warranty_claim' || type.contains('evidence')) {
          result['evidence']!.add(url);
        } else if (type == 'before') {
          result['before']!.add(url);
        } else if (type == 'after') {
          result['after']!.add(url);
        } else {
          result['evidence']!.add(url);
        }
      }
    } catch (e) {
      debugPrint('[DODO][WarrantiesRepository] Error fetching grouped rework images: $e');
    }

    return result;
  }

  /// Explicitly mark a warranty claim as Resolved
  Future<void> markWarrantyResolved(String warrantyId) async {
    await _client.from('service_warranties').update({
      'status': 'Resolved',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', warrantyId);
  }

  /// Approve a warranty claim:
  /// 1. Updates service_warranties status to 'Approved'
  /// 2. Updates rework booking status to 'pending' (ready for assignment workflow)
  /// 3. Dispatches customer notification
  Future<void> approveWarrantyClaim({
    required String warrantyId,
    required String? reworkBookingId,
    required String customerId,
    required String bookingNumber,
  }) async {
    final nowIso = DateTime.now().toIso8601String();

    // 1. Update warranty status
    await _client.from('service_warranties').update({
      'status': 'Approved',
      'updated_at': nowIso,
    }).eq('id', warrantyId);

    // 2. Move rework booking to pending assignment if present
    if (reworkBookingId != null && reworkBookingId.isNotEmpty) {
      try {
        await _client.from('bookings').update({
          'status': 'pending',
          'dispatch_status': 'idle',
          'updated_at': nowIso,
        }).eq('id', reworkBookingId);
      } catch (e) {
        debugPrint('[DODO][WarrantiesRepository] Warning: Rework booking update failed: $e');
      }
    }

    // 3. Customer notification
    try {
      await _client.from('notifications').insert({
        'user_type': 'customer',
        'user_id': customerId,
        'title': 'Warranty Claim Approved',
        'message': 'Your warranty claim for Booking #$bookingNumber has been approved. A technician will be assigned shortly.',
        'notification_type': 'warranty_claim',
        'is_read': false,
        'entity_type': 'service_warranty',
        'entity_id': warrantyId,
      });
    } catch (e) {
      debugPrint('[DODO][WarrantiesRepository] Warning: Notification insert failed: $e');
    }
  }

  /// Reject a warranty claim:
  /// 1. Updates service_warranties status to 'Rejected' with rejection notes
  /// 2. Updates rework booking status to 'cancelled' if present
  /// 3. Dispatches customer notification with mandatory rejection reason
  Future<void> rejectWarrantyClaim({
    required String warrantyId,
    required String? reworkBookingId,
    required String customerId,
    required String bookingNumber,
    required String reason,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw Exception('Rejection reason is mandatory.');
    }

    final nowIso = DateTime.now().toIso8601String();

    // 1. Update warranty status with rejection notes
    await _client.from('service_warranties').update({
      'status': 'Rejected',
      'notes': cleanReason,
      'updated_at': nowIso,
    }).eq('id', warrantyId);

    // 2. Cancel rework booking if present
    if (reworkBookingId != null && reworkBookingId.isNotEmpty) {
      try {
        await _client.from('bookings').update({
          'status': 'cancelled',
          'updated_at': nowIso,
        }).eq('id', reworkBookingId);
      } catch (e) {
        debugPrint('[DODO][WarrantiesRepository] Warning: Cancel rework booking failed: $e');
      }
    }

    // 3. Customer notification with reason
    try {
      await _client.from('notifications').insert({
        'user_type': 'customer',
        'user_id': customerId,
        'title': 'Warranty Claim Status Update',
        'message': 'Your warranty claim for Booking #$bookingNumber was rejected.\nReason: $cleanReason',
        'notification_type': 'warranty_claim',
        'is_read': false,
        'entity_type': 'service_warranty',
        'entity_id': warrantyId,
      });
    } catch (e) {
      debugPrint('[DODO][WarrantiesRepository] Warning: Notification insert failed: $e');
    }
  }
}
