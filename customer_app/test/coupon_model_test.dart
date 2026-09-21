import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/models/coupon_model.dart';

CouponModel _coupon({
  bool isActive = true,
  String discountType = 'percentage',
  double discountValue = 10.0,
  double? minOrderAmount,
  double? maxDiscountAmount,
  int? usageLimit,
  int usedCount = 0,
  DateTime? validFrom,
  DateTime? validTo,
}) =>
    CouponModel(
      id: 'c1',
      code: 'TEST10',
      discountType: discountType,
      discountValue: discountValue,
      isActive: isActive,
      minOrderAmount: minOrderAmount,
      maxDiscountAmount: maxDiscountAmount,
      usageLimit: usageLimit,
      usedCount: usedCount,
      validFrom: validFrom,
      validTo: validTo,
    );

void main() {
  group('CouponModel.validate', () {
    test('active coupon with no restrictions is valid', () {
      expect(_coupon().validate(500.0), isNull);
    });

    test('inactive coupon is invalid', () {
      expect(_coupon(isActive: false).validate(500.0), isNotNull);
    });

    test('expired coupon (validTo in past) is invalid', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      expect(_coupon(validTo: past).validate(500.0), isNotNull);
    });

    test('coupon not yet valid (validFrom in future) is invalid', () {
      final future = DateTime.now().add(const Duration(days: 1));
      expect(_coupon(validFrom: future).validate(500.0), isNotNull);
    });

    test('coupon within valid date range is valid', () {
      final from = DateTime.now().subtract(const Duration(days: 7));
      final to = DateTime.now().add(const Duration(days: 7));
      expect(_coupon(validFrom: from, validTo: to).validate(500.0), isNull);
    });

    test('usage limit reached is invalid', () {
      expect(_coupon(usageLimit: 5, usedCount: 5).validate(500.0), isNotNull);
    });

    test('usage count below limit is valid', () {
      expect(_coupon(usageLimit: 10, usedCount: 4).validate(500.0), isNull);
    });

    test('below minimum order amount is invalid', () {
      expect(_coupon(minOrderAmount: 500.0).validate(300.0), isNotNull);
    });

    test('exactly at minimum order amount is valid', () {
      expect(_coupon(minOrderAmount: 300.0).validate(300.0), isNull);
    });

    test('above minimum order amount is valid', () {
      expect(_coupon(minOrderAmount: 200.0).validate(500.0), isNull);
    });

    test('no usage limit means unlimited', () {
      expect(_coupon(usageLimit: null, usedCount: 9999).validate(500.0), isNull);
    });
  });

  group('CouponModel.calculateDiscount — percentage', () {
    test('10% of 500 = 50', () {
      expect(_coupon(discountType: 'percentage', discountValue: 10.0).calculateDiscount(500.0), 50.0);
    });

    test('100% of 200 = 200 (capped at subtotal)', () {
      expect(_coupon(discountType: 'percentage', discountValue: 100.0).calculateDiscount(200.0), 200.0);
    });

    test('percentage with max cap — discount below cap', () {
      // 10% of 300 = 30, cap = 100 → 30
      final c = _coupon(discountType: 'percentage', discountValue: 10.0, maxDiscountAmount: 100.0);
      expect(c.calculateDiscount(300.0), 30.0);
    });

    test('percentage with max cap — discount hits cap', () {
      // 50% of 400 = 200, cap = 100 → 100
      final c = _coupon(discountType: 'percentage', discountValue: 50.0, maxDiscountAmount: 100.0);
      expect(c.calculateDiscount(400.0), 100.0);
    });

    test('zero subtotal gives zero discount', () {
      expect(_coupon().calculateDiscount(0.0), 0.0);
    });

    test('zero discount value gives zero', () {
      expect(_coupon(discountValue: 0.0).calculateDiscount(500.0), 0.0);
    });
  });

  group('CouponModel.calculateDiscount — flat', () {
    test('flat ₹100 off 500 = 100', () {
      expect(_coupon(discountType: 'flat', discountValue: 100.0).calculateDiscount(500.0), 100.0);
    });

    test('flat discount larger than subtotal clamps to subtotal', () {
      // flat ₹500 off ₹300 → capped at 300
      expect(_coupon(discountType: 'flat', discountValue: 500.0).calculateDiscount(300.0), 300.0);
    });

    test('flat discount equal to subtotal = subtotal', () {
      expect(_coupon(discountType: 'flat', discountValue: 200.0).calculateDiscount(200.0), 200.0);
    });
  });

  group('CouponModel.discountLabel', () {
    test('percentage label without cap', () {
      expect(_coupon(discountType: 'percentage', discountValue: 10.0).discountLabel, '10% off');
    });

    test('percentage label with cap', () {
      expect(
        _coupon(discountType: 'percentage', discountValue: 20.0, maxDiscountAmount: 150.0).discountLabel,
        '20% off (up to ₹150)',
      );
    });

    test('flat label', () {
      expect(_coupon(discountType: 'flat', discountValue: 75.0).discountLabel, '₹75 off');
    });
  });

  group('CouponModel.fromMap', () {
    test('parses all fields correctly', () {
      final now = DateTime.now();
      final c = CouponModel.fromMap({
        'id': 'x1',
        'code': 'SUMMER20',
        'description': 'Summer deal',
        'discount_type': 'percentage',
        'discount_value': 20,
        'min_order_amount': 300.0,
        'max_discount_amount': 200.0,
        'usage_limit': 50,
        'used_count': 12,
        'valid_from': now.subtract(const Duration(days: 1)).toIso8601String(),
        'valid_to': now.add(const Duration(days: 30)).toIso8601String(),
        'is_active': true,
      });
      expect(c.code, 'SUMMER20');
      expect(c.discountType, 'percentage');
      expect(c.discountValue, 20.0);
      expect(c.usageLimit, 50);
      expect(c.usedCount, 12);
      expect(c.isActive, true);
    });

    test('defaults used_count to 0 when absent', () {
      final c = CouponModel.fromMap({
        'id': 'x2',
        'code': 'ABC',
        'discount_type': 'flat',
        'discount_value': 50,
        'is_active': false,
      });
      expect(c.usedCount, 0);
      expect(c.isActive, false);
    });
  });
}
