import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../cart/providers/cart_provider.dart';
import '../services/service_charge_service.dart';

/// Total service charge for the current cart.
/// Resolved server-side via resolve_service_charge_for_cart RPC.
/// Hierarchical: each item's nearest SC-enabled ancestor is used; deduped.
final serviceChargeTotalProvider = FutureProvider<double>((ref) async {
  final items = ref.watch(cartProvider);
  return ServiceChargeService().resolveCartServiceCharge(items);
});
