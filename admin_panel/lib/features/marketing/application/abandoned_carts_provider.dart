import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../settings/application/providers/settings_providers.dart';
import '../data/abandoned_carts_repository.dart';

final abandonedCartsRepositoryProvider =
    Provider<AbandonedCartsRepository>((ref) {
  return AbandonedCartsRepository(Supabase.instance.client);
});

final abandonedCartsProvider =
    FutureProvider.autoDispose<List<AbandonedCart>>((ref) {
  final settings = ref.watch(settingsNotifierProvider).valueOrNull ?? {};

  final valueStr = SettingsNotifier.effectiveValue(
      settings, 'abandoned_cart_inactivity_value');
  final unit = SettingsNotifier.effectiveValue(
      settings, 'abandoned_cart_inactivity_unit');

  final value = int.tryParse(valueStr) ?? 6;
  final threshold = switch (unit) {
    'minutes' => Duration(minutes: value),
    'days'    => Duration(days: value),
    _         => Duration(hours: value), // default: hours
  };

  return ref
      .read(abandonedCartsRepositoryProvider)
      .getAbandonedCarts(inactivityThreshold: threshold);
});
