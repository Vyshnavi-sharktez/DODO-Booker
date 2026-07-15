class VendorBookingRow {
  final String bookingId;
  final String vendorId;
  final DateTime completedAt;
  final double bookingGross;
  final double commissionAmount;
  final double netVendorAmount;
  final String commissionLabel;
  final bool isPaid;
  final String? settlementId;
  final DateTime? settledAt;
  final String? referenceNumber;

  const VendorBookingRow({
    required this.bookingId,
    required this.vendorId,
    required this.completedAt,
    required this.bookingGross,
    required this.commissionAmount,
    required this.netVendorAmount,
    required this.commissionLabel,
    required this.isPaid,
    this.settlementId,
    this.settledAt,
    this.referenceNumber,
  });
}
