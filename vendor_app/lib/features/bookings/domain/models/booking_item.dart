class BookingItem {
  final String serviceId;
  final String serviceName;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  const BookingItem({
    required this.serviceId,
    required this.serviceName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  factory BookingItem.fromMap(Map<String, dynamic> map) {
    final service = (map['catalog_nodes'] ?? map['services']) as Map<String, dynamic>?;
    final name = (service?['name'] as String?)?.isNotEmpty == true
        ? service!['name'] as String
        : (map['service_name'] as String?) ?? '';
    return BookingItem(
      serviceId: (map['service_id'] as String?) ?? '',
      serviceName: name,
      quantity: (map['quantity'] as int?) ?? 1,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0.0,
      totalPrice: (map['total_price'] as num?)?.toDouble() ?? 0.0,
    );
  }

  String get displayLabel =>
      quantity > 1 ? '$serviceName × $quantity' : serviceName;
}
