class BookingItem {
  final String serviceId;
  final String serviceName;
  final String? categoryName;
  final String? subcategoryName;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  const BookingItem({
    required this.serviceId,
    required this.serviceName,
    this.categoryName,
    this.subcategoryName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  factory BookingItem.fromJson(Map<String, dynamic> json) {
    // Key is 'catalog_nodes' after FK retargeting; fall back to 'services'
    // for any rows loaded from cache before the migration applied.
    final service = (json['catalog_nodes'] ?? json['services']) as Map<String, dynamic>?;
    return BookingItem(
      serviceId: (json['service_id'] as String?) ?? '',
      serviceName: (service?['name'] as String?) ?? '',
      categoryName: null,     // not available from catalog_nodes join
      subcategoryName: null,
      quantity: (json['quantity'] as int?) ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
