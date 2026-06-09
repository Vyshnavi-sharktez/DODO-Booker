import 'service_attribute_option.dart';

class ServiceAttribute {
  final String id;
  final String serviceId;
  final String name;
  final String fieldType;
  final bool isRequired;
  final List<ServiceAttributeOption> options;
  final DateTime? createdAt;

  const ServiceAttribute({
    required this.id,
    required this.serviceId,
    required this.name,
    required this.fieldType,
    required this.isRequired,
    required this.options,
    this.createdAt,
  });

  bool get hasOptions =>
      fieldType == 'dropdown' ||
      fieldType == 'radio' ||
      fieldType == 'checkbox';

  factory ServiceAttribute.fromMap(Map<String, dynamic> map) {
    final rawOptions =
        map['service_attribute_options'] as List<dynamic>? ?? [];
    final options = rawOptions
        .map((o) => ServiceAttributeOption.fromMap(o as Map<String, dynamic>))
        .toList();

    return ServiceAttribute(
      id: map['id'] as String,
      serviceId: map['service_id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      fieldType: map['field_type'] as String? ?? 'text',
      isRequired: map['is_required'] as bool? ?? false,
      options: options,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  ServiceAttribute copyWith({
    String? serviceId,
    String? name,
    String? fieldType,
    bool? isRequired,
    List<ServiceAttributeOption>? options,
  }) {
    return ServiceAttribute(
      id: id,
      serviceId: serviceId ?? this.serviceId,
      name: name ?? this.name,
      fieldType: fieldType ?? this.fieldType,
      isRequired: isRequired ?? this.isRequired,
      options: options ?? this.options,
      createdAt: createdAt,
    );
  }
}
