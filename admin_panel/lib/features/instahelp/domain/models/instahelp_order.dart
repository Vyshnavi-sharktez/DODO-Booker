import '../../../bookings/domain/models/booking.dart';

class InstaHelpOrder {
  final Booking booking;
  final String modeType; // 'scheduled' | 'instant'
  final String durationLabel;
  final int durationMinutes;
  final double basePrice;
  final double finalPrice;

  const InstaHelpOrder({
    required this.booking,
    required this.modeType,
    required this.durationLabel,
    required this.durationMinutes,
    required this.basePrice,
    required this.finalPrice,
  });

  static InstaHelpOrder fromBookingMap(Map<String, dynamic> map) {
    final ihList = map['instahelp_bookings'] as List<dynamic>? ?? [];
    final ih = ihList.isNotEmpty
        ? ihList.first as Map<String, dynamic>
        : <String, dynamic>{};
    return InstaHelpOrder(
      booking: Booking.fromMap(map),
      modeType: ih['mode_type'] as String? ?? 'scheduled',
      durationLabel: ih['duration_label'] as String? ?? '',
      durationMinutes: (ih['duration_minutes'] as num?)?.toInt() ?? 0,
      basePrice: (ih['base_price'] as num?)?.toDouble() ?? 0.0,
      finalPrice: (ih['final_price'] as num?)?.toDouble() ?? 0.0,
    );
  }

  InstaHelpOrder copyWith({Booking? booking}) => InstaHelpOrder(
        booking: booking ?? this.booking,
        modeType: modeType,
        durationLabel: durationLabel,
        durationMinutes: durationMinutes,
        basePrice: basePrice,
        finalPrice: finalPrice,
      );
}
