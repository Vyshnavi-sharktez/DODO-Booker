import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tax_settings_model.dart';
import '../services/tax_service.dart';

final taxSettingsProvider = FutureProvider<TaxSettingsModel>(
  (ref) => TaxService().getSettings(),
);

/// Scoped tax resolution: global master switch → relationship-scoped → node-scoped → global fallback.
/// If the global tax is disabled, returns the global (disabled) model immediately
/// without consulting catalog overrides.
/// Key: ({serviceId, parentNodeId?}).  When parentNodeId is null falls back to global.
final resolvedTaxProvider = FutureProvider.family<TaxSettingsModel,
    ({String serviceId, String? parentNodeId})>(
  (ref, key) async {
    final global = await ref.watch(taxSettingsProvider.future);
    if (!global.isEnabled) return global;
    return TaxService().getResolvedTaxForService(key.serviceId, key.parentNodeId);
  },
);
