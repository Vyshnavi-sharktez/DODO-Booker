import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/preferred_vendor_model.dart';

export '../models/preferred_vendor_model.dart';

typedef _ServiceLocationKey = ({
  String serviceId,
  String? parentNodeId,
  double? lat,
  double? lng,
});

/// Returns preferred vendors configured for [serviceId] that serve the
/// customer's [lat]/[lng] coordinates.  When coordinates are null, returns all
/// configured vendors (admin preview / fallback).
final preferredVendorsForServiceProvider = FutureProvider.autoDispose
    .family<List<PreferredVendorModel>, _ServiceLocationKey>((ref, key) async {
  final client = Supabase.instance.client;

  final config = await client.rpc('resolve_catalog_module_config', params: {
    'p_module': 'preferred_vendors',
    'p_service_id': key.serviceId,
    'p_parent_id': key.parentNodeId,
  });
  if (config == null) return [];

  final cfg = Map<String, dynamic>.from(config as Map);
  if (!(cfg['is_enabled'] as bool? ?? false)) return [];

  final vendorIds =
      (cfg['vendor_ids'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          [];
  if (vendorIds.isEmpty) return [];

  final result = await client.rpc(
    'get_preferred_vendors_by_ids_and_location',
    params: {
      'p_vendor_ids': vendorIds,
      'p_lat': key.lat,
      'p_lng': key.lng,
    },
  );
  if (result == null) return [];
  return (result as List<dynamic>)
      .map((r) => PreferredVendorModel.fromMap(r as Map<String, dynamic>))
      .toList();
});

// ── Vendor busy status ────────────────────────────────────────────────────────

typedef _VendorBusyKey = ({
  String vendorId,
  String date, // YYYY-MM-DD — the booking date the customer is selecting for
});

/// Returns `true` when [vendorId] has an active (accepted / en-route /
/// started / in-progress / awaiting-verification) booking on [date].
///
/// Derived entirely from booking status via the SECURITY DEFINER
/// `get_vendor_busy_status` RPC — no manual is_busy flag stored anywhere.
///
/// [p_now_minutes] is passed as 0 so the check covers the whole day:
/// any active booking on [date] (regardless of scheduled time) resolves
/// the vendor as BUSY.  Resets to AVAILABLE automatically when the booking
/// reaches Completed, Cancelled, or Rejected.
///
/// autoDispose ensures the value is re-fetched fresh each time the vendor
/// cards enter the tree (e.g. customer navigates back to the address step).
final vendorBusyProvider = FutureProvider.autoDispose
    .family<bool, _VendorBusyKey>((ref, key) async {
  final client = Supabase.instance.client;
  try {
    debugPrint('[DODO][PV BUSY] vendor=${key.vendorId}, date=${key.date}');
    final result = await client.rpc('get_vendor_busy_status', params: {
      'p_vendor_id': key.vendorId,
      'p_service_date': key.date,
      'p_now_minutes': 0,
    });
    debugPrint('[DODO][PV BUSY] RPC result=$result');
    final rows = result as List;
    if (rows.isEmpty) {
      debugPrint('[DODO][PV BUSY] isBusy=false (no rows)');
      return false;
    }
    final isBusy =
        (rows.first as Map<String, dynamic>)['is_busy'] as bool? ?? false;
    debugPrint('[DODO][PV BUSY] isBusy=$isBusy');
    return isBusy;
  } catch (e) {
    debugPrint('[DODO][PV BUSY] RPC error: $e — treating as available');
    return false;
  }
});
