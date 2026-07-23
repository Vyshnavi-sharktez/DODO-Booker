import '../../../models/service_model.dart';
import '../../catalog/models/catalog_node_model.dart';

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
    final serviceJson = (json['catalog_nodes'] ?? json['services']) as Map<String, dynamic>;
    return WishlistItemModel(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      serviceId: json['service_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      service: ServiceModel.fromJson(serviceJson),
    );
  }

  // Constructs from a separate wishlist row + catalog_nodes_view map.
  // Used by WishlistService.fetchWishlist() to avoid the broken
  // catalog_nodes(*) PostgREST embed: wishlists.node_id is NULL for items
  // added before the fix, so the embed returns null and crashes fromJson().
  factory WishlistItemModel.fromNodeMap({
    required String id,
    required String customerId,
    required String serviceId,
    required DateTime createdAt,
    required Map<String, dynamic> nodeData,
  }) {
    final node = CatalogNodeModel.fromMap(nodeData);
    return WishlistItemModel(
      id: id,
      customerId: customerId,
      serviceId: serviceId,
      createdAt: createdAt,
      service: ServiceModel(
        id: node.id,
        name: node.name,
        description: node.description,
        imageUrl: node.imageUrl,
        startingPrice: node.basePrice ?? 0.0,
        durationMinutes: node.estimatedDuration,
        categoryName: node.parentName,
        rating: node.rating,
        reviewCount: node.reviewCount,
        isFeatured: node.isFeatured,
        isActive: node.isActive,
      ),
    );
  }
}
