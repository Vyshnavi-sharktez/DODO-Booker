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
    final service = json['services'] as Map<String, dynamic>?;
    final category = service?['categories'] as Map<String, dynamic>?;
    final sub = service?['sub_categories'] as Map<String, dynamic>?;
    return BookingItem(
      serviceId: (json['service_id'] as String?) ?? '',
      serviceName: (service?['name'] as String?) ?? '',
      categoryName: category?['name'] as String?,
      subcategoryName: sub?['name'] as String?,
      quantity: (json['quantity'] as int?) ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
