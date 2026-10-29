import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/call_config_repository.dart';
import '../../domain/models/call_provider_config.dart';

final callConfigRepositoryProvider = Provider<CallConfigRepository>((ref) {
  return CallConfigRepository(Supabase.instance.client);
});

final callConfigProvider = FutureProvider<CallProviderConfig>((ref) {
  return ref.watch(callConfigRepositoryProvider).fetchConfig();
});

// Lightweight boolean used by vendor/customer apps to gate the call button
final callEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    final config = await ref.watch(callConfigProvider.future);
    return config.isEnabled && config.isConfigured;
  } catch (_) {
    return false;
  }
});
