import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/instahelp_duration_model.dart';
import '../models/instahelp_activity_model.dart';
import '../models/instahelp_financial_config_model.dart';
import '../models/instahelp_slot_model.dart';
import '../models/instahelp_vendor_model.dart';
import '../services/instahelp_service.dart';

final instaHelpServiceProvider = Provider<InstaHelpService>(
  (_) => InstaHelpService(),
);

// Vendor-specific modes — vendor_id = vendorId
final instaHelpVendorModeIdsProvider =
    FutureProvider.autoDispose.family<Map<String, String>, String>(
        (ref, vendorId) async {
  return ref.read(instaHelpServiceProvider).fetchModeIds(vendorId: vendorId);
});

// Vendors offering InstaHelp near a coordinate, filtered by mode type.
// Real-time: re-fetches whenever instahelp_modes changes (vendor toggles a mode).
typedef _IHLocationKey = ({double lat, double lng, String? modeType});

final instaHelpVendorsProvider = StreamProvider.autoDispose
    .family<List<InstaHelpVendorModel>, _IHLocationKey>((ref, key) {
  final service = ref.read(instaHelpServiceProvider);
  final controller = StreamController<List<InstaHelpVendorModel>>();

  Future<void> fetch() async {
    try {
      final rows = await service.fetchVendorsForLocation(
          key.lat, key.lng, modeType: key.modeType);
      if (!controller.isClosed) {
        controller.add(rows.map(InstaHelpVendorModel.fromMap).toList());
      }
    } catch (e, st) {
      if (!controller.isClosed) controller.addError(e, st);
    }
  }

  fetch();

  final channelName =
      'ih_vendors_${key.lat}_${key.lng}_${key.modeType ?? 'all'}';
  final channel = Supabase.instance.client
      .channel(channelName)
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'instahelp_modes',
        callback: (_) => fetch(),
      )
      .subscribe();

  ref.onDispose(() {
    channel.unsubscribe();
    controller.close();
  });

  return controller.stream;
});

final instaHelpDurationsProvider =
    FutureProvider.autoDispose.family<List<InstaHelpDurationModel>, String>(
        (ref, modeId) async {
  return ref.read(instaHelpServiceProvider).fetchDurations(modeId);
});

// Key: (modeId, date as ISO string)
typedef _DateKey = ({String modeId, String dateIso});

typedef _DateAvailability = ({bool isAvailable, String? message});

final instaHelpDateAvailabilityProvider =
    FutureProvider.autoDispose.family<_DateAvailability, _DateKey>((ref, key) async {
  final date = DateTime.parse(key.dateIso);
  return ref.read(instaHelpServiceProvider).checkDateAvailable(key.modeId, date);
});

// Key: (modeId, durationId, date as ISO string)
typedef _SlotsKey = ({String modeId, String durationId, String dateIso});

final instaHelpSlotsProvider =
    FutureProvider.autoDispose.family<List<InstaHelpSlotModel>, _SlotsKey>(
        (ref, key) async {
  final date = DateTime.parse(key.dateIso);
  return ref
      .read(instaHelpServiceProvider)
      .fetchSlots(key.modeId, key.durationId, date);
});

// Key: modeId
final instaHelpInstantAvailabilityProvider =
    FutureProvider.autoDispose.family<InstaHelpInstantAvailability, String>(
        (ref, modeId) async {
  return ref
      .read(instaHelpServiceProvider)
      .checkInstantAvailability(modeId);
});

// Key: modeId
final instaHelpActivitiesProvider =
    FutureProvider.autoDispose.family<List<InstaHelpActivityModel>, String>(
        (ref, modeId) async {
  return ref.read(instaHelpServiceProvider).fetchActivities(modeId);
});

// Key: modeId — streams real-time updates from Supabase
final instaHelpFinancialConfigProvider = StreamProvider.autoDispose
    .family<InstaHelpFinancialConfigModel?, String>((ref, modeId) {
  return ref.read(instaHelpServiceProvider).streamFinancialConfig(modeId);
});
