class CartItem {
  final String serviceId;
  final String serviceName;
  final String? imageUrl;
  final double unitPrice;
  final int quantity;

  /// The UUID of the original row in the legacy `services` table.
  /// Non-null for migrated catalog nodes; null for brand-new catalog nodes.
  /// Used as `service_id` in `booking_items` to satisfy the FK to services(id).
  final String? legacyId;

  /// Resolved from catalog_nodes.minimum_order_amount at the time the item was
  /// added (or synced). Null means no minimum applies to this service.
  final double? minimumOrderAmount;

  const CartItem({
    required this.serviceId,
    required this.serviceName,
    this.imageUrl,
    required this.unitPrice,
    required this.quantity,
    this.legacyId,
    this.minimumOrderAmount,
  });

  CartItem copyWith({int? quantity}) => CartItem(
        serviceId: serviceId,
        serviceName: serviceName,
        imageUrl: imageUrl,
        unitPrice: unitPrice,
        quantity: quantity ?? this.quantity,
        legacyId: legacyId,
        minimumOrderAmount: minimumOrderAmount,
      );

  double get totalPrice => unitPrice * quantity;

  Map<String, dynamic> toJson() => {
        'serviceId': serviceId,
        'serviceName': serviceName,
        'imageUrl': imageUrl,
        'unitPrice': unitPrice,
        'quantity': quantity,
        if (legacyId != null) 'legacyId': legacyId,
        if (minimumOrderAmount != null)
          'minimumOrderAmount': minimumOrderAmount,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        serviceId: json['serviceId'] as String,
        serviceName: json['serviceName'] as String,
        imageUrl: json['imageUrl'] as String?,
        unitPrice: (json['unitPrice'] as num).toDouble(),
        quantity: json['quantity'] as int,
        legacyId: json['legacyId'] as String?,
        minimumOrderAmount: (json['minimumOrderAmount'] as num?)?.toDouble(),
      );
}
