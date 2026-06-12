class Wallet {
  const Wallet({
    required this.id,
    required this.vendorId,
    this.balance = 0.0,
    this.totalEarned = 0.0,
    this.totalWithdrawn = 0.0,
    this.updatedAt,
  });

  final String id;
  final String vendorId;
  final double balance;
  final double totalEarned;
  final double totalWithdrawn;
  final DateTime? updatedAt;

  factory Wallet.fromMap(Map<String, dynamic> map) {
    return Wallet(
      id: map['id'] as String,
      vendorId: map['vendor_id'] as String? ?? '',
      balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
      totalEarned: (map['total_earned'] as num?)?.toDouble() ?? 0.0,
      totalWithdrawn: (map['total_withdrawn'] as num?)?.toDouble() ?? 0.0,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }
}
