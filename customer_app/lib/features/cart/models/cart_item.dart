class CartItem {
  final String serviceId;
  final String serviceName;
  final String? imageUrl;
  final double unitPrice;
  final int quantity;

  /// Resolved from catalog_nodes.minimum_order_amount at the time the item was
  /// added (or synced). Null means no minimum applies to this service.
  final double? minimumOrderAmount;

  /// The catalog_node.id of the parent through which the customer navigated
  /// to reach this service.  Null when the path is unknown (e.g. deep-links).
  /// Used by the scoped config resolver for Tax, Loyalty, Scheduling, Commission.
  final String? parentNodeId;

  const CartItem({
    required this.serviceId,
    required this.serviceName,
    this.imageUrl,
    required this.unitPrice,
    required this.quantity,
    this.minimumOrderAmount,
    this.parentNodeId,
  });

  CartItem copyWith({int? quantity, String? parentNodeId}) => CartItem(
        serviceId: serviceId,
        serviceName: serviceName,
        imageUrl: imageUrl,
        unitPrice: unitPrice,
        quantity: quantity ?? this.quantity,
        minimumOrderAmount: minimumOrderAmount,
        parentNodeId: parentNodeId ?? this.parentNodeId,
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
        if (parentNodeId != null) 'parentNodeId': parentNodeId,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        serviceId: json['serviceId'] as String,
        serviceName: json['serviceName'] as String,
        imageUrl: json['imageUrl'] as String?,
        unitPrice: (json['unitPrice'] as num).toDouble(),
        quantity: json['quantity'] as int,
        minimumOrderAmount: (json['minimumOrderAmount'] as num?)?.toDouble(),
        parentNodeId: json['parentNodeId'] as String?,
      );
}
