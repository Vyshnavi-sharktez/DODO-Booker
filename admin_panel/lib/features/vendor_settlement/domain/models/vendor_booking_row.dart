class VendorBookingRow {
  final String bookingId;
  final String vendorId;
  final DateTime completedAt;

  /// Total amount the customer paid (booking.total_amount, tax-inclusive).
  final double bookingGross;

  /// Pre-tax service amount (booking.subtotal).
  /// For legacy paid rows where the snapshot predates this field, this is 0.
  final double subtotalBeforeTax;

  /// Implicit tax: booking.total_amount − booking.subtotal + discount_amount.
  /// 0 for legacy paid rows.
  final double taxAmount;

  /// True when subtotalBeforeTax / taxAmount are populated (all new rows).
  /// False for paid rows settled before the tax-breakdown migration.
  final bool hasTaxBreakdown;

  /// Platform Commission deducted from the pre-tax service amount.
  final double commissionAmount;

  /// Vendor's net earnings: subtotalBeforeTax − commissionAmount (new rows).
  /// For legacy paid rows this is the stored snapshot value.
  final double netVendorAmount;

  /// Human-readable commission rate label, e.g. "15.0%", "Mixed", "10.0% (locked)".
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
    required this.subtotalBeforeTax,
    required this.taxAmount,
    required this.hasTaxBreakdown,
    required this.commissionAmount,
    required this.netVendorAmount,
    required this.commissionLabel,
    required this.isPaid,
    this.settlementId,
    this.settledAt,
    this.referenceNumber,
  });
}
