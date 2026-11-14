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
  /// via [parentNodeId].  Always checks the global master switch first by reading
  /// directly from DB (bypasses any Riverpod provider cache), so a disabled
  /// global is always respected even when called directly from service layer.
  Future<TaxSettingsModel> getResolvedTaxForService(
    String serviceId,
    String? parentNodeId,
  ) async {
    // Always fetch global fresh — authoritative master switch, not provider cache
    final globalModel = await getSettings();
    if (!globalModel.isEnabled) {
      debugPrint('[DODO][Tax] global tax is OFF — skipping catalog resolution');
      return globalModel;
    }

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
          final cfg = Map<String, dynamic>.from(result);
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
        debugPrint('[DODO][Tax] RPC returned null — using global');
      } catch (e) {
        debugPrint('[DODO][Tax] RPC exception: $e — using global');
      }
    } else {
      // Vendor custom service — check catalog_node_configs with custom_service_id
      try {
        final row = await _client
            .from('catalog_node_configs')
            .select('config')
            .eq('module', 'tax')
            .eq('custom_service_id', serviceId)
            .maybeSingle();
        if (row != null) {
          final cfg = Map<String, dynamic>.from(row['config'] as Map);
          if (cfg['is_enabled'] == true) {
            final model = TaxSettingsModel(
              isEnabled: true,
              taxName: (cfg['tax_name'] as String?) ?? globalModel.taxName,
              taxType: (cfg['tax_type'] as String?) ?? globalModel.taxType,
              taxValue: (cfg['tax_value'] as num?)?.toDouble() ?? globalModel.taxValue,
              applyOnServices: true,
              applyOnAddons: true,
              applyOnPackages: false,
              displaySeparately: true,
            );
            debugPrint('[DODO][Tax] → custom_service config: ${model.taxValue}% (${model.taxName})');
            return model;
          }
        }
        debugPrint('[DODO][Tax] no custom_service config found — using global');
      } catch (e) {
        debugPrint('[DODO][Tax] custom_service lookup exception: $e — using global');
      }
    }
    debugPrint('[DODO][Tax] → global result: ${globalModel.taxValue}% (${globalModel.taxName})');
    return globalModel;
  }
}
