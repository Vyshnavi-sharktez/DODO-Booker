import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/abandoned_carts_repository.dart';

final abandonedCartsRepositoryProvider =
    Provider<AbandonedCartsRepository>((ref) {
  return AbandonedCartsRepository(Supabase.instance.client);
});

final abandonedCartsProvider =
    FutureProvider.autoDispose<List<AbandonedCart>>((ref) {
  return ref.read(abandonedCartsRepositoryProvider).getAbandonedCarts();
});
