import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/loyalty_service.dart';
import '../models/loyalty_settings_model.dart';
import '../models/customer_loyalty_model.dart';
import '../models/loyalty_transaction_model.dart';

final _loyaltyService = LoyaltyService();

final loyaltySettingsProvider =
    FutureProvider<LoyaltySettingsModel>((ref) => _loyaltyService.getSettings());

final customerLoyaltyProvider =
    FutureProvider<CustomerLoyaltyModel>((ref) => _loyaltyService.getCustomerLoyalty());

final loyaltyTransactionsProvider =
    FutureProvider<List<LoyaltyTransactionModel>>(
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
