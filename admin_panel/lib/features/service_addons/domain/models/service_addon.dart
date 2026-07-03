class ServiceAddon {
  final String id;
  final String serviceId;
  final String name;
  final String? description;
  final double price;
  final bool isActive;
  final DateTime? createdAt;

  const ServiceAddon({
    required this.id,
    required this.serviceId,
    required this.name,
    this.description,
    required this.price,
    required this.isActive,
    this.createdAt,
  });

  factory ServiceAddon.fromMap(Map<String, dynamic> map) {
    return ServiceAddon(
      id: map['id'] as String,
      serviceId: map['service_id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      description: map['description'] as String?,
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      isActive: map['is_active'] as bool? ?? true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  ServiceAddon copyWith({
    String? name,
    String? description,
    double? price,
    bool? isActive,
  }) {
    return ServiceAddon(
      id: id,
      serviceId: serviceId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }
}
