import 'package:flutter/foundation.dart';
import 'catalog_service.dart';

/// Represents a vendor_services row joined with its full catalog entry.
/// All service data (name, price, category, etc.) comes from [catalog] —
/// the same catalog_nodes_view record the Admin panel uses.
@immutable
class AssignedService {
  const AssignedService({
    required this.id,
    required this.serviceId,
    required this.isActive,
    required this.catalog,
  });

  final String id;         // vendor_services.id
  final String serviceId;  // catalog_node.id
  final bool isActive;     // vendor toggle
  final CatalogService catalog;

  String get serviceName => catalog.name;
  String? get categoryName => catalog.parentName;
  String? get subCategoryName => null;
  double get basePrice => catalog.basePrice;

  factory AssignedService.fromMap(Map<String, dynamic> map) {
    final catalogMap =
        Map<String, dynamic>.from(map['catalog'] as Map? ?? const {});
    return AssignedService(
      id: map['id'] as String,
      serviceId: (map['service_id'] as String?) ?? '',
      isActive: (map['is_active'] as bool?) ?? true,
      catalog: CatalogService.fromMap(catalogMap),
    );
  }
}
