enum SettlementStatus { noEarnings, settled, pendingPayment }

class VendorEarningsSummary {
  final String vendorId;
  final String vendorName;
  final String? ownerName;
  final bool isActive;
  final int completedJobs;
  final double grossEarnings;
  final double totalSettled;
  final DateTime? lastSettlementAt;

  const VendorEarningsSummary({
    required this.vendorId,
    required this.vendorName,
    this.ownerName,
    required this.isActive,
    required this.completedJobs,
    required this.grossEarnings,
    required this.totalSettled,
    this.lastSettlementAt,
  });

  double get pendingSettlement =>
      (grossEarnings - totalSettled).clamp(0.0, double.infinity);

  SettlementStatus get settlementStatus {
    if (completedJobs == 0) return SettlementStatus.noEarnings;
    if (pendingSettlement <= 0) return SettlementStatus.settled;
    return SettlementStatus.pendingPayment;
  }
}
