enum TransactionType { credit, debit, withdrawal, settlement }

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.vendorId,
    required this.type,
    required this.amount,
    this.description,
    this.bookingId,
    this.createdAt,
  });

  final String id;
  final String vendorId;
  final TransactionType type;
  final double amount;
  final String? description;
  final String? bookingId;
  final DateTime? createdAt;

  factory WalletTransaction.fromMap(Map<String, dynamic> map) {
    return WalletTransaction(
      id: map['id'] as String,
      vendorId: map['vendor_id'] as String? ?? '',
      type: TransactionType.values.firstWhere(
        (t) => t.name == (map['type'] as String? ?? 'credit'),
        orElse: () => TransactionType.credit,
      ),
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      description: map['description'] as String?,
      bookingId: map['booking_id'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }
}
