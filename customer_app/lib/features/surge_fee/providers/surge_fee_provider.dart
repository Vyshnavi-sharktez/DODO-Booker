import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/surge_fee_model.dart';
import '../services/surge_fee_service.dart';

final surgeFeeSettingsProvider = FutureProvider<SurgeFeeModel>(
  (ref) => SurgeFeeService().getSettings(),
);

/// Scoped surge resolution: global master switch → relationship-scoped → node-scoped → global fallback.
/// If the global surge fee is disabled, returns the global (disabled) model immediately
/// without consulting catalog overrides.
/// Key: ({serviceId, parentNodeId?}).
final resolvedSurgeFeeProvider = FutureProvider.family<SurgeFeeModel,
    ({String serviceId, String? parentNodeId})>(
  (ref, key) async {
    final global = await ref.watch(surgeFeeSettingsProvider.future);
    if (!global.isEnabled) return global;
    return SurgeFeeService()
        .getResolvedSurgeFeeForService(key.serviceId, key.parentNodeId);
  },
);
