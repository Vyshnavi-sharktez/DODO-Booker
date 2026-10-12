class BookingItem {
  final String serviceId;
  final String serviceName; // snapshotted catalog service name
  final String itemName;    // custom item product label (when serviceId is empty)
  final String categoryName; // custom category label (when serviceId is empty)
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  const BookingItem({
    required this.serviceId,
    required this.serviceName,
    this.itemName = '',
    this.categoryName = '',
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  // For catalog items: serviceName is the snapshotted catalog name.
  // For custom items: itemName is the product name.
  String get displayName =>
      serviceName.isNotEmpty ? serviceName : (itemName.isNotEmpty ? itemName : '—');

  factory BookingItem.fromMap(Map<String, dynamic> map) {
    final service =
        (map['catalog_nodes'] ?? map['services']) as Map<String, dynamic>?;
    return BookingItem(
      serviceId: (map['service_id'] as String?) ?? '',
      serviceName: (service?['name'] as String?) ??
          (map['service_name'] as String?) ??
          '',
      itemName: (map['item_name'] as String?) ?? '',
      categoryName: (map['category_name'] as String?) ?? '',
      quantity: (map['quantity'] as int?) ?? 1,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0.0,
      totalPrice: (map['total_price'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
