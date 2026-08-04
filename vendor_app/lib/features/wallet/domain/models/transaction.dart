enum TransactionType {
  topUp,
  commission,
  penalty,
  adjustment;

  static TransactionType fromString(String? value) {
    switch (value) {
      case 'top_up':
      case 'credit':
        return TransactionType.topUp;
      case 'commission':
      case 'debit':
        return TransactionType.commission;
      case 'penalty':
      case 'withdrawal':
        return TransactionType.penalty;
      case 'adjustment':
      case 'settlement':
        return TransactionType.adjustment;
      default:
        return TransactionType.topUp;
    }
  }

  String toDbValue() {
    switch (this) {
      case TransactionType.topUp:
        return 'top_up';
      case TransactionType.commission:
        return 'commission';
      case TransactionType.penalty:
        return 'penalty';
      case TransactionType.adjustment:
        return 'adjustment';
    }
  }
}

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.vendorId,
    required this.type,
    required this.amount,
    this.balanceAfter = 0.0,
    this.referenceId,
    this.referenceType,
    this.description,
    this.createdBy,
    this.createdAt,
  });

  final String id;
  final String vendorId;
  final TransactionType type;
  final double amount;
  final double balanceAfter;
  final String? referenceId;
  final String? referenceType;
  final String? description;
  final String? createdBy;
  final DateTime? createdAt;

  /// Backward-compatibility getter for bookingId
  String? get bookingId => referenceType == 'booking' ? referenceId : null;

  factory WalletTransaction.fromMap(Map<String, dynamic> map) {
    return WalletTransaction(
      id: map['id'] as String,
      vendorId: map['vendor_id'] as String? ?? '',
      type: TransactionType.fromString(map['type'] as String?),
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      balanceAfter: (map['balance_after'] as num?)?.toDouble() ?? 0.0,
      referenceId: map['reference_id'] as String? ?? map['booking_id'] as String?,
      referenceType: map['reference_type'] as String? ??
          (map['booking_id'] != null ? 'booking' : null),
      description: map['description'] as String?,
      createdBy: map['created_by'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }
}
