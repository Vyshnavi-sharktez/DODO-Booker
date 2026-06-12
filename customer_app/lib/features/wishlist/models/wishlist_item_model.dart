import '../../../models/service_model.dart';

class WishlistItemModel {
  final String id;
  final String customerId;
  final String serviceId;
  final DateTime createdAt;
  final ServiceModel service;

  const WishlistItemModel({
    required this.id,
    required this.customerId,
    required this.serviceId,
    required this.createdAt,
    required this.service,
  });

  factory WishlistItemModel.fromJson(Map<String, dynamic> json) {
    final serviceJson = json['services'] as Map<String, dynamic>;
    return WishlistItemModel(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      serviceId: json['service_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      service: ServiceModel.fromJson(serviceJson),
    );
  }
}
