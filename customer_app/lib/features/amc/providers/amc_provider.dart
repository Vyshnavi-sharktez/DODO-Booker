import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/amc_plan_model.dart';

export '../models/amc_plan_model.dart';

final amcPlansProvider = FutureProvider.autoDispose
    .family<List<AmcPlanModel>, String>((ref, nodeId) async {
  debugPrint('[DODO][AMC] Fetching plans for nodeId=$nodeId');
  try {
    final rows = await Supabase.instance.client
        .from('catalog_node_amc_plans')
        .select('amc_plans(*)')
        .eq('node_id', nodeId);

    final plans = <AmcPlanModel>[];
    for (final row in rows) {
      final planData = row['amc_plans'] as Map<String, dynamic>?;
      if (planData == null) continue;
      final plan = AmcPlanModel.fromMap(planData);
      if (plan.isActive) plans.add(plan);
    }
    debugPrint('[DODO][AMC] Found ${plans.length} active plans');
    return plans;
  } catch (e, st) {
    debugPrint('[DODO][AMC] Fetch error: $e\n$st');
    return [];
  }
});
