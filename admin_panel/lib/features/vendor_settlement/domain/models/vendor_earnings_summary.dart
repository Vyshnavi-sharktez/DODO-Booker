enum SettlementStatus { noEarnings, settled, pendingPayment }

class VendorEarningsSummary {
  final String vendorId;
  final String vendorName;
  final String? ownerName;
  final bool isActive;
  final int pendingOrdersCount;
  final int paidOrdersCount;
  final double totalPending;
  final double totalPaid;
  final DateTime? lastSettlementAt;

  const VendorEarningsSummary({
    required this.vendorId,
    required this.vendorName,
    this.ownerName,
    required this.isActive,
    required this.pendingOrdersCount,
    required this.paidOrdersCount,
    required this.totalPending,
    required this.totalPaid,
    this.lastSettlementAt,
  });

  int get completedJobs => pendingOrdersCount + paidOrdersCount;
  double get pendingSettlement => totalPending;

  SettlementStatus get settlementStatus {
    if (completedJobs == 0) return SettlementStatus.noEarnings;
    if (pendingOrdersCount == 0) return SettlementStatus.settled;
    return SettlementStatus.pendingPayment;
  }
}
