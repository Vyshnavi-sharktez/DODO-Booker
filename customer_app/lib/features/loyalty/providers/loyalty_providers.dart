import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/loyalty_service.dart';
import '../models/loyalty_settings_model.dart';
import '../models/customer_loyalty_model.dart';
import '../models/loyalty_transaction_model.dart';
import '../../auth/providers/auth_provider.dart';

final _loyaltyService = LoyaltyService();

final loyaltySettingsProvider =
    FutureProvider<LoyaltySettingsModel>((ref) => _loyaltyService.getSettings());

// Watches auth state so the provider re-runs after login/logout, ensuring
// loyalty points are fetched from the correct customer on mobile fresh sessions.
// autoDispose so the balance re-fetches each time the loyalty modal opens,
// ensuring points earned from completed bookings are always shown fresh.
final customerLoyaltyProvider =
    FutureProvider.autoDispose<CustomerLoyaltyModel>((ref) {
  ref.watch(authNotifierProvider);
  return _loyaltyService.getCustomerLoyalty();
});

final loyaltyTransactionsProvider =
    FutureProvider.autoDispose<List<LoyaltyTransactionModel>>(
        (ref) => _loyaltyService.getTransactions());

/// Scoped loyalty resolution: returns the resolved loyalty config JSONB for a
/// service, or null when no catalog override is found (caller uses global rate).
/// Key: ({serviceId, parentNodeId?}).
final resolvedLoyaltyConfigProvider =
    FutureProvider.family<Map<String, dynamic>?, ({String serviceId, String? parentNodeId})>(
  (ref, key) => _loyaltyService.getResolvedLoyaltyConfigForService(
    key.serviceId,
    key.parentNodeId,
  ),
);
