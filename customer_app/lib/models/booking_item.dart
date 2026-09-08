class BookingItem {
  final String serviceId;
  final String? customServiceId;
  final String serviceName;
  final String? categoryName;
  final String? subcategoryName;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final String? catalogParentNodeId;

  const BookingItem({
    required this.serviceId,
    this.customServiceId,
    required this.serviceName,
    this.categoryName,
    this.subcategoryName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.catalogParentNodeId,
  });

  factory BookingItem.fromJson(Map<String, dynamic> json) {
    // catalog_nodes join for DODO services; vendor_service_requests for custom services.
    final catalogNode =
        (json['catalog_nodes'] ?? json['services']) as Map<String, dynamic>?;
    final vsr =
        json['vendor_service_requests'] as Map<String, dynamic>?;
    return BookingItem(
      serviceId: (json['service_id'] as String?) ?? '',
      customServiceId: json['custom_service_id'] as String?,
      serviceName: (catalogNode?['name'] as String?) ??
          (vsr?['service_name'] as String?) ??
          '',
      categoryName: null,
      subcategoryName: null,
      quantity: (json['quantity'] as int?) ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0.0,
      catalogParentNodeId: json['catalog_parent_node_id'] as String?,
    );
  }
}
