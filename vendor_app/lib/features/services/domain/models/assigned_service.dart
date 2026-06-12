class AssignedService {
  const AssignedService({
    required this.id,
    required this.serviceId,
    required this.serviceName,
    this.categoryName,
    this.basePrice = 0.0,
    this.isActive = true,
  });

  final String id;
  final String serviceId;
  final String serviceName;
  final String? categoryName;
  final double basePrice;
  final bool isActive;

  factory AssignedService.fromMap(Map<String, dynamic> map) {
    return AssignedService(
      id: map['id'] as String,
      serviceId: map['service_id'] as String? ?? '',
      serviceName: map['service_name'] as String? ?? '',
      categoryName: map['category_name'] as String?,
      basePrice: (map['base_price'] as num?)?.toDouble() ?? 0.0,
      isActive: map['is_active'] as bool? ?? true,
    );
  }
}
