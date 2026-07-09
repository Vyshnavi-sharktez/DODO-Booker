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
