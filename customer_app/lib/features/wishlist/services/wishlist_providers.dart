import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import 'wishlist_service.dart';
import '../models/wishlist_item_model.dart';

final wishlistServiceProvider = Provider<WishlistService>(
  (ref) => WishlistService(),
);

/// Watched by HeartButton widgets. Re-fetches automatically on login/logout.
final wishlistedIdsProvider = FutureProvider<Set<String>>((ref) async {
  final isAuth = ref.watch(isAuthenticatedProvider);
  if (!isAuth) return {};
  return ref.read(wishlistServiceProvider).fetchWishlistedIds();
});

/// Full wishlist with joined service data, used by WishlistScreen.
final wishlistItemsProvider = FutureProvider<List<WishlistItemModel>>((ref) async {
  final isAuth = ref.watch(isAuthenticatedProvider);
  if (!isAuth) return [];
  return ref.read(wishlistServiceProvider).fetchWishlist();
});
