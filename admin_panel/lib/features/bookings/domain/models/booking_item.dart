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
    final service = map['services'] as Map<String, dynamic>?;
    return BookingItem(
      serviceId: (map['service_id'] as String?) ?? '',
      serviceName: (service?['name'] as String?) ?? '',
      quantity: (map['quantity'] as int?) ?? 1,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0.0,
      totalPrice: (map['total_price'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
