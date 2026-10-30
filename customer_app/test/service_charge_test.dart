import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/features/cart/models/cart_item.dart';

// Mirrors the server-side resolution logic for unit-testing SC math.
// The actual hierarchy walk happens in the RPC; these tests cover:
//   1. Checkout formula with SC included
//   2. Deduplication logic (same ancestor → charged once)
//   3. Independent accumulation (different ancestors → each charged)
//   4. Edge cases (empty cart, no parentNodeId, AMC/custom items filtered)

// Pure formula mirror of CheckoutService.createCartBooking with SC:
//   gross = subtotal + surge + pvFee + tax + serviceCharge
//   total = (gross - discount).clamp(0, ∞)
double _computeTotal({
  required List<CartItem> items,
  double serviceCharge = 0.0,
  double taxAmount = 0.0,
  double surgeAmount = 0.0,
  double pvFeeAmount = 0.0,
  double discountAmount = 0.0,
  double globalAddonsTotal = 0.0,
}) {
  final subtotal =
      items.fold(0.0, (s, i) => s + i.totalPrice) + globalAddonsTotal;
  final gross = subtotal + surgeAmount + pvFeeAmount + taxAmount + serviceCharge;
  return (gross - discountAmount).clamp(0.0, double.infinity);
}

CartItem _item(
  String id,
  double price,
  int qty, {
  String? parentNodeId,
  bool isAmc = false,
  String? customServiceId,
}) =>
    CartItem(
      bookingId: 'bk',
      serviceId: id,
      serviceName: id,
      unitPrice: price,
      quantity: qty,
      parentNodeId: parentNodeId,
      isAmc: isAmc,
      customServiceId: customServiceId,
    );

// Simulates the eligibility filter from ServiceChargeService.resolveCartServiceCharge.
List<Map<String, String?>> _eligibleCartItems(List<CartItem> items) => items
    .where((i) => !i.isCustomService && !i.isAmc && i.parentNodeId != null)
    .map((i) => {
          'service_id': i.serviceId,
          'parent_node_id': i.parentNodeId,
        })
    .toList();

// Simulates deduplication: given a list of (parentNodeId → amount) entries,
// returns the total charge applying each ancestor at most once.
double _resolveCharges(List<({String nodeId, double amount})> chargeMap) {
  final seen = <String>{};
  var total = 0.0;
  for (final entry in chargeMap) {
    if (seen.add(entry.nodeId)) total += entry.amount;
  }
  return total;
}

void main() {
  // ── Checkout formula with service charge ──────────────────────────────────
  group('Checkout total with service charge', () {
    test('SC is added to gross before discount', () {
      final items = [_item('s1', 500.0, 1)];
      expect(
        _computeTotal(items: items, serviceCharge: 100.0),
        600.0,
      );
    });

    test('SC does not go below zero even with large discount', () {
      final items = [_item('s1', 100.0, 1)];
      expect(
        _computeTotal(items: items, serviceCharge: 50.0, discountAmount: 200.0),
        0.0,
      );
    });

    test('SC + surge + tax accumulate correctly', () {
      final items = [_item('s1', 300.0, 1)];
      expect(
        _computeTotal(
          items: items,
          serviceCharge: 50.0,
          surgeAmount: 30.0,
          taxAmount: 20.0,
        ),
        400.0,
      );
    });

    test('zero SC does not change total', () {
      final items = [_item('s1', 500.0, 1)];
      expect(
        _computeTotal(items: items, serviceCharge: 0.0),
        _computeTotal(items: items),
      );
    });
  });

  // ── Eligibility filter ─────────────────────────────────────────────────────
  group('ServiceChargeService eligibility filter', () {
    test('excludes AMC items', () {
      final items = [
        _item('a1', 100.0, 1, parentNodeId: 'node-1', isAmc: true),
      ];
      expect(_eligibleCartItems(items), isEmpty);
    });

    test('excludes custom-service items', () {
      final items = [
        _item('c1', 100.0, 1,
            parentNodeId: 'node-1', customServiceId: 'cs-123'),
      ];
      expect(_eligibleCartItems(items), isEmpty);
    });

    test('excludes items without parentNodeId', () {
      final items = [_item('s1', 100.0, 1)];
      expect(_eligibleCartItems(items), isEmpty);
    });

    test('includes DODO catalog item with parentNodeId', () {
      final items = [
        _item('s1', 100.0, 1, parentNodeId: 'node-1'),
      ];
      final result = _eligibleCartItems(items);
      expect(result.length, 1);
      expect(result.first['parent_node_id'], 'node-1');
    });

    test('empty cart produces empty eligible list', () {
      expect(_eligibleCartItems([]), isEmpty);
    });

    test('mixed cart filters correctly', () {
      final items = [
        _item('s1', 100.0, 1, parentNodeId: 'node-1'),
        _item('a1', 200.0, 1, parentNodeId: 'node-2', isAmc: true),
        _item('c1', 150.0, 1,
            parentNodeId: 'node-3', customServiceId: 'cs-99'),
        _item('s2', 50.0, 1),
        _item('s3', 75.0, 2, parentNodeId: 'node-4'),
      ];
      final result = _eligibleCartItems(items);
      expect(result.length, 2);
      expect(result.map((e) => e['service_id']), containsAll(['s1', 's3']));
    });
  });

  // ── Deduplication (same ancestor) ─────────────────────────────────────────
  group('Ancestor deduplication', () {
    test('two items from same ancestor → charged once', () {
      // Both items resolve to node-A (₹80)
      final charges = [
        (nodeId: 'node-A', amount: 80.0),
        (nodeId: 'node-A', amount: 80.0),
      ];
      expect(_resolveCharges(charges), 80.0);
    });

    test('three items, two share ancestor → ancestor charged once', () {
      final charges = [
        (nodeId: 'node-A', amount: 50.0),
        (nodeId: 'node-A', amount: 50.0),
        (nodeId: 'node-B', amount: 30.0),
      ];
      expect(_resolveCharges(charges), 80.0);
    });

    test('all items share one ancestor → charged exactly once', () {
      final charges = List.generate(
          5, (_) => (nodeId: 'node-root', amount: 100.0));
      expect(_resolveCharges(charges), 100.0);
    });
  });

  // ── Independent accumulation (different ancestors) ─────────────────────────
  group('Independent ancestor accumulation', () {
    test('two items from different ancestors → both charged', () {
      final charges = [
        (nodeId: 'node-A', amount: 60.0),
        (nodeId: 'node-B', amount: 40.0),
      ];
      expect(_resolveCharges(charges), 100.0);
    });

    test('three items from three different ancestors → all charged', () {
      final charges = [
        (nodeId: 'node-A', amount: 50.0),
        (nodeId: 'node-B', amount: 75.0),
        (nodeId: 'node-C', amount: 25.0),
      ];
      expect(_resolveCharges(charges), 150.0);
    });

    test('zero-amount ancestor still deduplicates', () {
      final charges = [
        (nodeId: 'node-A', amount: 0.0),
        (nodeId: 'node-A', amount: 0.0),
        (nodeId: 'node-B', amount: 50.0),
      ];
      expect(_resolveCharges(charges), 50.0);
    });
  });

  // ── Full checkout with hierarchy results ────────────────────────────────────
  group('Checkout total with hierarchical SC', () {
    test('two items from same ancestor → SC charged once in total', () {
      final items = [
        _item('s1', 300.0, 1, parentNodeId: 'node-A'),
        _item('s2', 200.0, 1, parentNodeId: 'node-A'),
      ];
      // RPC would return 80 (node-A charged once)
      const sc = 80.0;
      expect(
        _computeTotal(items: items, serviceCharge: sc),
        580.0, // 500 + 80
      );
    });

    test('two items from different ancestors → SC charged independently', () {
      final items = [
        _item('s1', 300.0, 1, parentNodeId: 'node-A'),
        _item('s2', 200.0, 1, parentNodeId: 'node-B'),
      ];
      // RPC would return 110 (node-A=80 + node-B=30)
      const sc = 110.0;
      expect(
        _computeTotal(items: items, serviceCharge: sc),
        610.0, // 500 + 110
      );
    });
  });
}
