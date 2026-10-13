// Tests for multi-cart functionality: conflict auto-save, cart switching,
// clear-only-active behaviour, and saved-cart persistence helpers.
//
// CartNotifier tests use ProviderContainer without a running Flutter app.
// SharedPreferences is mocked so persistence calls are no-ops.
// Supabase calls are wrapped in try-catch inside the notifier and will fail
// silently when Supabase is uninitialised, which is expected in tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/features/cart/models/cart_item.dart';
import 'package:customer_app/features/cart/providers/cart_provider.dart';
import 'package:customer_app/features/cart/providers/saved_carts_provider.dart';
import 'package:customer_app/features/catalog/models/catalog_node_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

CartItem _item(String id, double price, int qty, {String? rootCategoryId}) =>
    CartItem(
      bookingId: 'bk_$id',
      serviceId: id,
      serviceName: id,
      unitPrice: price,
      quantity: qty,
      rootCategoryId: rootCategoryId,
    );

CatalogNodeModel _node(String id, String name, double price) =>
    CatalogNodeModel(
      id: id,
      name: name,
      slug: id,
      sortOrder: 0,
      isActive: true,
      isFeatured: false,
      isBookable: true,
      basePrice: price,
    );

ProviderContainer _makeContainer() => ProviderContainer();

// ── CartItem JSON serialisation ───────────────────────────────────────────────

void main() {
  group('CartItem JSON serialisation', () {
    test('rootCategoryId survives toJson / fromJson roundtrip', () {
      final item = _item('s1', 299.0, 1, rootCategoryId: 'root-ac');
      final restored = CartItem.fromJson(item.toJson());
      expect(restored.rootCategoryId, 'root-ac');
    });

    test('null rootCategoryId is omitted from JSON and restored as null', () {
      final item = _item('s1', 299.0, 1);
      final json = item.toJson();
      expect(json.containsKey('rootCategoryId'), isFalse);
      expect(CartItem.fromJson(json).rootCategoryId, isNull);
    });
  });

  // ── CartAddResult ─────────────────────────────────────────────────────────

  group('CartAddResult', () {
    test('enum has added and newCartStarted values', () {
      expect(CartAddResult.added, isNotNull);
      expect(CartAddResult.newCartStarted, isNotNull);
      expect(CartAddResult.values.length, 2);
    });
  });

  // ── SavedCartsNotifier ────────────────────────────────────────────────────

  group('SavedCartsNotifier state transitions', () {
    // Each test creates a fresh notifier; SharedPreferences is mocked so
    // _load() finds nothing and _persist() silently no-ops.
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('starts with an empty map', () {
      final n = SavedCartsNotifier();
      expect(n.state, isEmpty);
    });

    test('saveCart adds an entry', () {
      final n = SavedCartsNotifier();
      n.saveCart('root1', [_item('s1', 100, 1)]);
      expect(n.state['root1'], isNotNull);
      expect(n.state['root1']!.length, 1);
    });

    test('saveCart is a no-op when items is empty', () {
      final n = SavedCartsNotifier();
      n.saveCart('root1', []);
      expect(n.state, isEmpty);
    });

    test('saveCart overwrites an existing entry', () {
      final n = SavedCartsNotifier();
      n.saveCart('root1', [_item('s1', 100, 1)]);
      n.saveCart('root1', [_item('s2', 200, 2), _item('s3', 150, 1)]);
      expect(n.state['root1']!.length, 2);
    });

    test('takeCart removes and returns the correct items', () {
      final n = SavedCartsNotifier();
      n.saveCart('root1', [_item('s1', 100, 1)]);
      final taken = n.takeCart('root1');
      expect(taken, isNotNull);
      expect(taken!.first.serviceId, 's1');
      expect(n.state.containsKey('root1'), isFalse);
    });

    test('takeCart returns null for a missing key', () {
      final n = SavedCartsNotifier();
      expect(n.takeCart('nonexistent'), isNull);
    });

    test('removeCart deletes the entry', () {
      final n = SavedCartsNotifier();
      n.saveCart('root1', [_item('s1', 100, 1)]);
      n.removeCart('root1');
      expect(n.state.containsKey('root1'), isFalse);
    });

    test('multiple carts are stored independently', () {
      final n = SavedCartsNotifier();
      n.saveCart('root1', [_item('s1', 100, 1)]);
      n.saveCart('root2', [_item('s2', 200, 2)]);
      expect(n.state.length, 2);
      expect(n.state['root1']!.first.serviceId, 's1');
      expect(n.state['root2']!.first.serviceId, 's2');
    });

    test('removing one cart does not affect others', () {
      final n = SavedCartsNotifier();
      n.saveCart('root1', [_item('s1', 100, 1)]);
      n.saveCart('root2', [_item('s2', 200, 1)]);
      n.removeCart('root1');
      expect(n.state.containsKey('root1'), isFalse);
      expect(n.state.containsKey('root2'), isTrue);
    });
  });

  // ── CartNotifier multi-cart behaviour ─────────────────────────────────────

  group('CartNotifier multi-cart', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('addToCart returns added when cart is empty', () async {
      final c = _makeContainer();
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero); // let _load() complete

      final result = c.read(cartProvider.notifier).addToCart(
            _node('s1', 'AC Service', 299),
            rootCategoryId: 'root-ac',
          );
      expect(result, CartAddResult.added);
      expect(c.read(cartProvider).length, 1);
      expect(c.read(savedCartsProvider), isEmpty);
    });

    test('addToCart returns added for the same root category', () async {
      final c = _makeContainer();
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      c.read(cartProvider.notifier).addToCart(
            _node('s1', 'AC Service', 299),
            rootCategoryId: 'root-ac',
          );
      final result = c.read(cartProvider.notifier).addToCart(
            _node('s2', 'Deep Clean', 499),
            rootCategoryId: 'root-ac',
          );
      expect(result, CartAddResult.added);
      expect(c.read(cartProvider).length, 2);
      expect(c.read(savedCartsProvider), isEmpty);
    });

    test(
        'addToCart returns newCartStarted and saves old cart on root conflict',
        () async {
      final c = _makeContainer();
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      // Seed active cart with AC Services
      c.read(cartProvider.notifier).addToCart(
            _node('s1', 'AC Service', 299),
            rootCategoryId: 'root-ac',
          );

      // Add a Plumbing service — different root category
      final result = c.read(cartProvider.notifier).addToCart(
            _node('s2', 'Plumbing Fix', 199),
            rootCategoryId: 'root-plumbing',
          );

      expect(result, CartAddResult.newCartStarted);
      // Active cart now contains only the new item
      final active = c.read(cartProvider);
      expect(active.length, 1);
      expect(active.first.serviceId, 's2');
      expect(active.first.rootCategoryId, 'root-plumbing');
      // Old cart is saved
      expect(c.read(savedCartsProvider).containsKey('root-ac'), isTrue);
      expect(c.read(savedCartsProvider)['root-ac']!.length, 1);
    });

    test('clearCart clears active cart but retains saved carts', () async {
      final c = _makeContainer();
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      // Build active (root-ac) and then trigger a saved cart (root-plumbing)
      c.read(cartProvider.notifier).addToCart(
            _node('s1', 'AC Service', 299),
            rootCategoryId: 'root-ac',
          );
      c.read(cartProvider.notifier).addToCart(
            _node('s2', 'Plumbing Fix', 199),
            rootCategoryId: 'root-plumbing',
          );
      // Active: root-plumbing, Saved: root-ac

      c.read(cartProvider.notifier).clearCart();

      expect(c.read(cartProvider), isEmpty);
      // Saved cart for root-ac must survive
      expect(c.read(savedCartsProvider).containsKey('root-ac'), isTrue);
    });

    test('switchToCart makes the target cart active and saves the old one',
        () async {
      final c = _makeContainer();
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      // root-ac → active; root-plumbing gets saved
      c.read(cartProvider.notifier).addToCart(
            _node('s1', 'AC Service', 299),
            rootCategoryId: 'root-ac',
          );
      c.read(cartProvider.notifier).addToCart(
            _node('s2', 'Plumbing Fix', 199),
            rootCategoryId: 'root-plumbing',
          );
      // Active: root-plumbing (s2), Saved: root-ac (s1)

      c.read(cartProvider.notifier).switchToCart('root-ac');

      // root-ac is now active
      final active = c.read(cartProvider);
      expect(active.length, 1);
      expect(active.first.serviceId, 's1');
      // root-plumbing is now saved
      expect(c.read(savedCartsProvider).containsKey('root-plumbing'), isTrue);
      // root-ac is no longer saved
      expect(c.read(savedCartsProvider).containsKey('root-ac'), isFalse);
    });

    test('switchToCart is a no-op for a non-existent rootCategoryId', () async {
      final c = _makeContainer();
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      c.read(cartProvider.notifier).addToCart(
            _node('s1', 'AC Service', 299),
            rootCategoryId: 'root-ac',
          );
      c.read(cartProvider.notifier).switchToCart('nonexistent');

      // Active cart unchanged
      expect(c.read(cartProvider).length, 1);
      expect(c.read(cartProvider).first.serviceId, 's1');
    });

    test('after checkout clearCart, saved carts remain for future switch',
        () async {
      final c = _makeContainer();
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      c.read(cartProvider.notifier).addToCart(
            _node('s1', 'AC Service', 299),
            rootCategoryId: 'root-ac',
          );
      c.read(cartProvider.notifier).addToCart(
            _node('s2', 'Plumbing Fix', 199),
            rootCategoryId: 'root-plumbing',
          );
      // root-ac saved, root-plumbing active

      // Simulate post-checkout clear
      c.read(cartProvider.notifier).clearCart();
      expect(c.read(cartProvider), isEmpty);

      // Customer switches to the remaining saved cart
      c.read(cartProvider.notifier).switchToCart('root-ac');
      expect(c.read(cartProvider).first.serviceId, 's1');
    });

    test(
        'third conflict evicts oldest saved cart, keeping total at 2',
        () async {
      final c = _makeContainer();
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);

      // Conflict 1: root-ac → saved, root-plumbing becomes active.
      c.read(cartProvider.notifier).addToCart(
            _node('s1', 'AC Service', 299),
            rootCategoryId: 'root-ac',
          );
      c.read(cartProvider.notifier).addToCart(
            _node('s2', 'Plumbing Fix', 199),
            rootCategoryId: 'root-plumbing',
          );
      // Conflict 2: root-plumbing → saved (now 2 saved), trimToOne() evicts
      // root-ac (oldest), leaving exactly 1 saved cart + 1 active = 2 total.
      c.read(cartProvider.notifier).addToCart(
            _node('s3', 'Pest Control', 399),
            rootCategoryId: 'root-pest',
          );

      // Exactly 1 saved cart — no third cart is ever created.
      expect(c.read(savedCartsProvider).length, 1);
      // Oldest saved cart (root-ac) was evicted to stay within the 2-cart cap.
      expect(c.read(savedCartsProvider).containsKey('root-ac'), isFalse);
      // Most-recently saved cart (root-plumbing) is retained.
      expect(c.read(savedCartsProvider).containsKey('root-plumbing'), isTrue);
      // Newest item is in the active cart.
      expect(c.read(cartProvider).first.rootCategoryId, 'root-pest');
    });
  });
}
