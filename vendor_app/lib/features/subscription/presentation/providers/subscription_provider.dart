import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/subscription_repository.dart';
import '../../domain/models/subscription_plan.dart';
import '../../domain/models/vendor_subscription.dart';

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>(
  (ref) => SubscriptionRepository(ref.watch(supabaseClientProvider)),
);

final activePlansProvider = FutureProvider.autoDispose<List<SubscriptionPlan>>((ref) {
  return ref.read(subscriptionRepositoryProvider).fetchActivePlans();
});

final mySubscriptionProvider =
    FutureProvider.autoDispose<VendorSubscription?>((ref) {
  final vendor = ref.watch(currentVendorUserProvider);
  if (vendor == null) return Future.value(null);
  return ref.read(subscriptionRepositoryProvider).fetchMySubscription(vendor.id);
});

final subscriptionSettingsProvider =
    FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final result =
      await ref.read(subscriptionRepositoryProvider).fetchSubscriptionSettings();
  debugPrint('[DODO][Settings] provider resolved → $result');
  return result;
});

final subscriptionEnabledProvider = Provider.autoDispose<bool>((ref) {
  final settings = ref.watch(subscriptionSettingsProvider).valueOrNull;
  return settings?['subscription_enabled'] == 'true';
});

final isExpiringSoonProvider = Provider.autoDispose<bool>((ref) {
  final sub = ref.watch(mySubscriptionProvider).valueOrNull;
  return sub?.isExpiringSoon ?? false;
});
