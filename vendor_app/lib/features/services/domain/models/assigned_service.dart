class AssignedService {
  const AssignedService({
    required this.id,
    required this.serviceId,
    required this.serviceName,
    this.categoryName,
    this.subCategoryName,
    this.basePrice = 0.0,
    this.customPrice,
    this.isActive = true,
  });

  final String id; // vendor_services.id
  final String serviceId;
  final String serviceName;
  final String? categoryName;
  final String? subCategoryName;
  final double basePrice;
  final double? customPrice;
  final bool isActive;

  double get effectivePrice => customPrice ?? basePrice;

  factory AssignedService.fromMap(Map<String, dynamic> map) {
    final service = map['services'] as Map<String, dynamic>? ?? {};
    final category = service['categories'] as Map<String, dynamic>?;
    final subCategory = service['sub_categories'] as Map<String, dynamic>?;

    return AssignedService(
      id: map['id'] as String,
      serviceId: map['service_id'] as String? ?? '',
      serviceName: service['name'] as String? ?? '',
      categoryName: category?['name'] as String?,
      subCategoryName: subCategory?['name'] as String?,
      basePrice: (service['base_price'] as num?)?.toDouble() ?? 0.0,
      customPrice: (map['custom_price'] as num?)?.toDouble(),
      isActive: map['is_active'] as bool? ?? true,
    );
  }
}
