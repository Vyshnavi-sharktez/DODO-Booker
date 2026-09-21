import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/features/cart/models/cart_item.dart';
import 'package:customer_app/features/tax/models/tax_settings_model.dart';
import 'package:customer_app/models/coupon_model.dart';

// Mirrors the formula in CheckoutService.createCartBooking (checkout_service.dart):
//   subtotal   = items.fold(0.0, (s, i) => s + i.totalPrice)
//   gross      = subtotal + surgeAmount + pvFeeAmount + taxAmount
//   totalAmount = (gross - discountAmount).clamp(0.0, double.infinity)
double _computeTotal({
  required List<CartItem> items,
  double taxAmount = 0.0,
  double surgeAmount = 0.0,
  double pvFeeAmount = 0.0,
  double discountAmount = 0.0,
}) {
  final subtotal = items.fold(0.0, (s, i) => s + i.totalPrice);
  final gross = subtotal + surgeAmount + pvFeeAmount + taxAmount;
  return (gross - discountAmount).clamp(0.0, double.infinity);
}

CartItem _item(String id, double price, int qty) => CartItem(
      bookingId: 'bk',
      serviceId: id,
      serviceName: id,
      unitPrice: price,
      quantity: qty,
    );

void main() {
  group('CartItem.totalPrice', () {
    test('unit price multiplied by quantity', () {
      expect(_item('s1', 299.0, 2).totalPrice, 598.0);
    });

    test('quantity of 1 returns unit price unchanged', () {
      expect(_item('s1', 149.5, 1).totalPrice, 149.5);
    });

    test('fractional unit price preserved', () {
      expect(_item('s1', 99.99, 3).totalPrice, closeTo(299.97, 0.001));
    });
  });

  group('Checkout subtotal (cart fold)', () {
    test('single item subtotal', () {
      final items = [_item('s1', 500.0, 1)];
      final sub = items.fold(0.0, (s, i) => s + i.totalPrice);
      expect(sub, 500.0);
    });

    test('multi-item subtotal', () {
      final items = [
        _item('s1', 299.0, 2), // 598
        _item('s2', 149.0, 1), // 149
      ];
      final sub = items.fold(0.0, (s, i) => s + i.totalPrice);
      expect(sub, 747.0);
    });
  });

  group('Checkout total formula', () {
    test('base total with no extras', () {
      expect(_computeTotal(items: [_item('s1', 500.0, 1)]), 500.0);
    });

    test('total includes tax', () {
      // 500 + 90 tax = 590
      expect(_computeTotal(items: [_item('s1', 500.0, 1)], taxAmount: 90.0), 590.0);
    });

    test('total includes surge fee', () {
      expect(_computeTotal(items: [_item('s1', 500.0, 1)], surgeAmount: 50.0), 550.0);
    });

    test('total includes preferred-vendor fee', () {
      expect(_computeTotal(items: [_item('s1', 500.0, 1)], pvFeeAmount: 75.0), 575.0);
    });

    test('discount is deducted from gross', () {
      // gross = 500 + 50 surge + 90 tax = 640; discount = 100 → 540
      final total = _computeTotal(
        items: [_item('s1', 500.0, 1)],
        taxAmount: 90.0,
        surgeAmount: 50.0,
        discountAmount: 100.0,
      );
      expect(total, 540.0);
    });

    test('discount exceeding gross clamps to zero', () {
      final total = _computeTotal(
        items: [_item('s1', 100.0, 1)],
        discountAmount: 500.0,
      );
      expect(total, 0.0);
    });

    test('discount exactly equal to gross yields zero', () {
      final total = _computeTotal(
        items: [_item('s1', 100.0, 1)],
        taxAmount: 18.0,
        discountAmount: 118.0,
      );
      expect(total, 0.0);
    });

    test('all fees combined', () {
      // subtotal=200, surge=30, pvFee=25, tax=36 → gross=291; discount=50 → 241
      final total = _computeTotal(
        items: [_item('s1', 200.0, 1)],
        surgeAmount: 30.0,
        pvFeeAmount: 25.0,
        taxAmount: 36.0,
        discountAmount: 50.0,
      );
      expect(total, 241.0);
    });

    test('multi-item cart with tax and discount', () {
      final items = [_item('s1', 299.0, 2), _item('s2', 149.0, 1)]; // subtotal = 747
      final total = _computeTotal(
        items: items,
        taxAmount: 134.46, // 18% of 747
        discountAmount: 100.0,
      );
      expect(total, closeTo(781.46, 0.01));
    });

    test('zero unit price item contributes nothing', () {
      final items = [_item('s1', 0.0, 5), _item('s2', 200.0, 1)];
      final total = _computeTotal(items: items);
      expect(total, 200.0);
    });
  });

  group('TaxSettingsModel.computeTax integration with checkout', () {
    test('18% tax on subtotal of 500 = 90', () {
      const model = TaxSettingsModel(
        isEnabled: true,
        taxName: 'GST',
        taxType: 'percentage',
        taxValue: 18.0,
        applyOnServices: true,
        applyOnAddons: true,
        applyOnPackages: false,
        displaySeparately: true,
      );
      final taxAmount = model.computeTax(500.0);
      final total = _computeTotal(
        items: [_item('s1', 500.0, 1)],
        taxAmount: taxAmount,
      );
      expect(taxAmount, 90.0);
      expect(total, 590.0);
    });

    test('disabled tax model yields zero tax and total equals subtotal', () {
      const model = TaxSettingsModel(
        isEnabled: false,
        taxName: 'GST',
        taxType: 'percentage',
        taxValue: 18.0,
        applyOnServices: true,
        applyOnAddons: true,
        applyOnPackages: false,
        displaySeparately: true,
      );
      final taxAmount = model.computeTax(500.0);
      expect(taxAmount, 0.0);
      expect(
        _computeTotal(items: [_item('s1', 500.0, 1)], taxAmount: taxAmount),
        500.0,
      );
    });
  });

  group('CouponModel.calculateDiscount integration with checkout', () {
    CouponModel makeCoupon({
      String type = 'percentage',
      double value = 10.0,
      double? max,
    }) =>
        CouponModel(
          id: 'c1',
          code: 'TEST10',
          discountType: type,
          discountValue: value,
          maxDiscountAmount: max,
          isActive: true,
        );

    test('10% coupon on 500 = 50 discount, total = 450', () {
      final discount = makeCoupon().calculateDiscount(500.0);
      final total = _computeTotal(
        items: [_item('s1', 500.0, 1)],
        discountAmount: discount,
      );
      expect(discount, 50.0);
      expect(total, 450.0);
    });

    test('flat ₹100 coupon on 400, total = 300', () {
      final discount = makeCoupon(type: 'flat', value: 100.0).calculateDiscount(400.0);
      final total = _computeTotal(
        items: [_item('s1', 400.0, 1)],
        discountAmount: discount,
      );
      expect(discount, 100.0);
      expect(total, 300.0);
    });
  });
}
