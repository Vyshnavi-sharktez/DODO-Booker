import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tax_settings_model.dart';
import '../services/tax_service.dart';

final taxSettingsProvider = FutureProvider<TaxSettingsModel>(
  (ref) => TaxService().getSettings(),
);

/// Scoped tax resolution: relationship-scoped → node-scoped → global fallback.
/// Key: ({serviceId, parentNodeId?}).  When parentNodeId is null falls back to global.
final resolvedTaxProvider = FutureProvider.family<TaxSettingsModel,
    ({String serviceId, String? parentNodeId})>(
  (ref, key) =>
      TaxService().getResolvedTaxForService(key.serviceId, key.parentNodeId),
);
