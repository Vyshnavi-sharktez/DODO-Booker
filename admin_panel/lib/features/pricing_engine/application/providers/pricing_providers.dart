import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../service_attributes/application/providers/service_attributes_providers.dart';
import '../../../services/application/providers/services_providers.dart';

// ── Calculator selection state ────────────────────────────────────────────────
// Maps attributeId → selected optionId for the live calculator panel.

class PricingCalculatorNotifier extends StateNotifier<Map<String, String>> {
  PricingCalculatorNotifier() : super({});

  void selectOption(String attributeId, String optionId) {
    state = {...state, attributeId: optionId};
  }

  void clearAttribute(String attributeId) {
    final next = Map<String, String>.from(state);
    next.remove(attributeId);
    state = next;
  }

  void reset() => state = {};
}

final pricingCalculatorProvider =
    StateNotifierProvider<PricingCalculatorNotifier, Map<String, String>>(
  (ref) => PricingCalculatorNotifier(),
);

// ── Live calculated price ─────────────────────────────────────────────────────
// Family-parameterised by serviceId so it reacts to the correct base price.

final calculatedPriceProvider = Provider.family<double, String>((ref, serviceId) {
  final services = ref.watch(servicesNotifierProvider).valueOrNull ?? [];
  final service = services.where((s) => s.id == serviceId).firstOrNull;
  if (service == null) return 0.0;

  final attributes =
      ref.watch(serviceAttributesNotifierProvider).valueOrNull ?? [];
  final selections = ref.watch(pricingCalculatorProvider);

  double total = service.basePrice;
  for (final attr in attributes) {
    final optionId = selections[attr.id];
    if (optionId != null) {
      final match = attr.options.where((o) => o.id == optionId).firstOrNull;
      if (match != null) total += match.priceAdjustment;
    }
  }
  return total;
});

// ── Breakdown list ────────────────────────────────────────────────────────────
// Returns (attributeName, optionName, priceAdjustment) for each selection.

final calculatorBreakdownProvider =
    Provider.family<List<(String, String, double)>, String>(
  (ref, serviceId) {
    final attributes =
        ref.watch(serviceAttributesNotifierProvider).valueOrNull ?? [];
    final selections = ref.watch(pricingCalculatorProvider);

    final result = <(String, String, double)>[];
    for (final attr in attributes) {
      final optionId = selections[attr.id];
      if (optionId != null) {
        final match = attr.options.where((o) => o.id == optionId).firstOrNull;
        if (match != null) result.add((attr.name, match.optionName, match.priceAdjustment));
      }
    }
    return result;
  },
);
