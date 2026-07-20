import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/surge_fee_model.dart';

class SurgeFeeService {
  final _client = Supabase.instance.client;

  Future<SurgeFeeModel> getSettings() async {
    try {
      final rows = await _client
          .from('surge_fee_settings')
          .select()
          .order('updated_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) return SurgeFeeModel.defaults;
      return SurgeFeeModel.fromJson(rows.first);
    } catch (_) {
      return SurgeFeeModel.defaults;
    }
  }

  /// Returns the most-specific surge config for [serviceId] navigated via
  /// [parentNodeId].  Always checks the global master switch first by reading
  /// directly from DB (bypasses any Riverpod provider cache), so a disabled
  /// global is always respected even if providers have stale cached values.
  Future<SurgeFeeModel> getResolvedSurgeFeeForService(
    String serviceId,
    String? parentNodeId,
  ) async {
    // Always fetch global fresh — authoritative master switch, not provider cache
    final globalModel = await getSettings();
    if (!globalModel.isEnabled) {
      debugPrint('[DODO][Surge] global surge is OFF — skipping catalog resolution');
      return globalModel;
    }

    debugPrint('[DODO][Surge] getResolvedSurgeFeeForService: '
        'serviceId=$serviceId  parentNodeId=$parentNodeId');
    if (parentNodeId != null) {
      try {
        final result = await _client.rpc(
          'resolve_catalog_module_config',
          params: {
            'p_module': 'surge',
            'p_service_id': serviceId,
            'p_parent_id': parentNodeId,
          },
        );
        debugPrint('[DODO][Surge] RPC raw result: $result');
        if (result != null && result is Map) {
          final cfg = Map<String, dynamic>.from(result);
          final model = SurgeFeeModel(
            isEnabled: (cfg['is_enabled'] as bool?) ?? true,
            surgeName: (cfg['surge_name'] as String?) ?? 'Surge Fee',
            surgeType: (cfg['surge_type'] as String?) ?? 'percentage',
            surgeValue: (cfg['surge_value'] as num?)?.toDouble() ?? 0.0,
            description: cfg['description'] as String?,
          );
          debugPrint('[DODO][Surge] → scoped result: ${model.surgeValue} (${model.surgeName})');
          return model;
        }
        debugPrint('[DODO][Surge] RPC returned null — using global');
      } catch (e) {
        debugPrint('[DODO][Surge] RPC exception: $e — using global');
      }
    } else {
      debugPrint('[DODO][Surge] parentNodeId is null — using global');
    }
    debugPrint('[DODO][Surge] → global result: ${globalModel.surgeValue} (${globalModel.surgeName})');
    return globalModel;
  }
}
