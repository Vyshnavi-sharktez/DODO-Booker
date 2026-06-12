import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/coupon_model.dart';
import 'coupon_service.dart';

final couponServiceProvider = Provider<CouponService>(
  (_) => CouponService(),
);

final activeCouponsProvider = FutureProvider<List<CouponModel>>(
  (ref) => ref.read(couponServiceProvider).fetchActiveCoupons(),
);

/// Holds the coupon selected during the current booking session.
/// Reset to null after the booking completes or fails.
final selectedCouponProvider = StateProvider<CouponModel?>((_) => null);
