import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/payment_gateway_config_repository.dart';
import '../../domain/models/payment_gateway_config.dart';

final paymentGatewayConfigRepositoryProvider =
    Provider<PaymentGatewayConfigRepository>((ref) {
  return PaymentGatewayConfigRepository(ref.watch(supabaseClientProvider));
});

// ── Notifier ──────────────────────────────────────────────────────────────────

class PaymentGatewayConfigNotifier
    extends StateNotifier<AsyncValue<List<PaymentGatewayConfig>>> {
  final PaymentGatewayConfigRepository _repo;

  PaymentGatewayConfigNotifier(this._repo)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchAll);
  }

  Future<void> refresh() => _load();

  Future<void> saveConfig(PaymentGatewayConfig config) async {
    await _repo.saveConfig(config);
    final current = state.valueOrNull ?? [];
    final updated = [
      for (final c in current)
        if (c.gateway == config.gateway) config else c,
    ];
    // If the gateway wasn't in the list yet, append it.
    if (!updated.any((c) => c.gateway == config.gateway)) {
      updated.add(config);
    }
    state = AsyncValue.data(updated);
  }

  Future<void> setSecret(
    String gateway,
    String secretName,
    String value,
  ) =>
      _repo.setSecret(gateway, secretName, value);

  Future<bool> secretIsSet(String gateway, String secretName) =>
      _repo.secretIsSet(gateway, secretName);

  PaymentGatewayConfig configFor(String gateway) {
    return state.valueOrNull
            ?.firstWhere(
              (c) => c.gateway == gateway,
              orElse: () => PaymentGatewayConfig.empty(gateway),
            ) ??
        PaymentGatewayConfig.empty(gateway);
  }
}

final paymentGatewayConfigNotifierProvider = StateNotifierProvider<
    PaymentGatewayConfigNotifier, AsyncValue<List<PaymentGatewayConfig>>>(
  (ref) => PaymentGatewayConfigNotifier(
    ref.watch(paymentGatewayConfigRepositoryProvider),
  ),
);
