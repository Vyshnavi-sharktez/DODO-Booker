class VendorSettlement {
  final String id;
  final String vendorId;
  final String vendorName;
  final double amount;
  final double balanceBefore;
  final double balanceAfter;
  final String? notes;
  final DateTime settledAt;
  final String settledBy;

  const VendorSettlement({
    required this.id,
    required this.vendorId,
    required this.vendorName,
    required this.amount,
    required this.balanceBefore,
    required this.balanceAfter,
    this.notes,
    required this.settledAt,
    required this.settledBy,
  });
}
