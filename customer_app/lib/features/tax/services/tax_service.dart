import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tax_settings_model.dart';

class TaxService {
  final _client = Supabase.instance.client;

  Future<TaxSettingsModel> getSettings() async {
    try {
      final row = await _client
          .from('tax_settings')
          .select()
          .limit(1)
          .maybeSingle();
      if (row == null) return TaxSettingsModel.defaults;
      return TaxSettingsModel.fromJson(row);
    } catch (_) {
      return TaxSettingsModel.defaults;
    }
  }

  /// Returns the most-specific tax config applicable for [serviceId] navigated
  /// via [parentNodeId].  Falls back to the global tax_settings row.
  Future<TaxSettingsModel> getResolvedTaxForService(
    String serviceId,
    String? parentNodeId,
  ) async {
    debugPrint('[DODO][Tax] getResolvedTaxForService: '
        'serviceId=$serviceId  parentNodeId=$parentNodeId');
    if (parentNodeId != null) {
      try {
        final result = await _client.rpc(
          'resolve_catalog_module_config',
          params: {
            'p_module': 'tax',
            'p_service_id': serviceId,
            'p_parent_id': parentNodeId,
          },
        );
        debugPrint('[DODO][Tax] RPC raw result: $result');
        if (result != null && result is Map) {
          final cfg = Map<String, dynamic>.from(result as Map);
          final model = TaxSettingsModel(
            isEnabled: (cfg['is_enabled'] as bool?) ?? true,
            taxName: (cfg['tax_name'] as String?) ?? 'GST',
            taxType: (cfg['tax_type'] as String?) ?? 'percentage',
            taxValue: (cfg['tax_value'] as num?)?.toDouble() ?? 18.0,
            applyOnServices: true,
            applyOnAddons: true,
            applyOnPackages: false,
            displaySeparately: true,
          );
          debugPrint('[DODO][Tax] → scoped result: ${model.taxValue}% (${model.taxName})');
          return model;
        }
        debugPrint('[DODO][Tax] RPC returned null — falling back to global');
      } catch (e) {
        debugPrint('[DODO][Tax] RPC exception: $e — falling back to global');
      }
    } else {
      debugPrint('[DODO][Tax] parentNodeId is null — skipping RPC, using global');
    }
    final global = await getSettings();
    debugPrint('[DODO][Tax] → global result: ${global.taxValue}% (${global.taxName})');
    return global;
  }
}
