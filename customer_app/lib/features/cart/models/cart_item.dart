class CartItem {
  final String serviceId;
  final String serviceName;
  final String? imageUrl;
  final double unitPrice;
  final int quantity;

  /// Resolved from catalog_nodes.minimum_order_amount at the time the item was
  /// added (or synced). Null means no minimum applies to this service.
  final double? minimumOrderAmount;

  const CartItem({
    required this.serviceId,
    required this.serviceName,
    this.imageUrl,
    required this.unitPrice,
    required this.quantity,
    this.minimumOrderAmount,
  });

  CartItem copyWith({int? quantity}) => CartItem(
        serviceId: serviceId,
        serviceName: serviceName,
        imageUrl: imageUrl,
        unitPrice: unitPrice,
        quantity: quantity ?? this.quantity,
        minimumOrderAmount: minimumOrderAmount,
      );

  double get totalPrice => unitPrice * quantity;

  Map<String, dynamic> toJson() => {
        'serviceId': serviceId,
        'serviceName': serviceName,
        'imageUrl': imageUrl,
        'unitPrice': unitPrice,
        'quantity': quantity,
        if (minimumOrderAmount != null)
          'minimumOrderAmount': minimumOrderAmount,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        serviceId: json['serviceId'] as String,
        serviceName: json['serviceName'] as String,
        imageUrl: json['imageUrl'] as String?,
        unitPrice: (json['unitPrice'] as num).toDouble(),
        quantity: json['quantity'] as int,
        minimumOrderAmount: (json['minimumOrderAmount'] as num?)?.toDouble(),
      );
}
