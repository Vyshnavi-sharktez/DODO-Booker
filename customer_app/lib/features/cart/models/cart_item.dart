class CartItem {
  final String serviceId;
  final String serviceName;
  final String? imageUrl;
  final double unitPrice;
  final int quantity;

  const CartItem({
    required this.serviceId,
    required this.serviceName,
    this.imageUrl,
    required this.unitPrice,
    required this.quantity,
  });

  CartItem copyWith({int? quantity}) => CartItem(
        serviceId: serviceId,
        serviceName: serviceName,
        imageUrl: imageUrl,
        unitPrice: unitPrice,
        quantity: quantity ?? this.quantity,
      );

  double get totalPrice => unitPrice * quantity;

  Map<String, dynamic> toJson() => {
        'serviceId': serviceId,
        'serviceName': serviceName,
        'imageUrl': imageUrl,
        'unitPrice': unitPrice,
        'quantity': quantity,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        serviceId: json['serviceId'] as String,
        serviceName: json['serviceName'] as String,
        imageUrl: json['imageUrl'] as String?,
        unitPrice: (json['unitPrice'] as num).toDouble(),
        quantity: json['quantity'] as int,
      );
}
