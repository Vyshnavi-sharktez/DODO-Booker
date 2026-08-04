class VendorWalletInfo {
  final String vendorId;
  final double availableBalance;
  final double pendingBalance;
  final double minimumRequiredBalance;
  final double? lastTopUpAmount;
  final DateTime? lastTopUpDate;

  const VendorWalletInfo({
    required this.vendorId,
    required this.availableBalance,
    required this.pendingBalance,
    required this.minimumRequiredBalance,
    this.lastTopUpAmount,
    this.lastTopUpDate,
  });

  bool get isEligible => availableBalance >= minimumRequiredBalance;

  String get statusLabel => isEligible ? 'Eligible' : 'Below Minimum';
}

class VendorWalletTransaction {
  final String id;
  final String vendorId;
  final String type; // 'top_up', 'commission', 'penalty', 'adjustment'
  final double amount;
  final double balanceAfter;
  final String? referenceId;
  final String? referenceType;
  final String? description;
  final DateTime createdAt;

  const VendorWalletTransaction({
    required this.id,
    required this.vendorId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.referenceId,
    this.referenceType,
    this.description,
    required this.createdAt,
  });

  factory VendorWalletTransaction.fromMap(Map<String, dynamic> map) {
    return VendorWalletTransaction(
      id: map['id'] as String,
      vendorId: map['vendor_id'] as String,
      type: map['type'] as String? ?? 'adjustment',
      amount: (map['amount'] as num).toDouble(),
      balanceAfter: (map['balance_after'] as num).toDouble(),
      referenceId: map['reference_id'] as String?,
      referenceType: map['reference_type'] as String?,
      description: map['description'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
