class ServiceAttributeOptionModel {
  final String id;
  final String attributeId;
  final String optionName;
  final double priceAdjustment;

  const ServiceAttributeOptionModel({
    required this.id,
    required this.attributeId,
    required this.optionName,
    this.priceAdjustment = 0.0,
  });

  factory ServiceAttributeOptionModel.fromJson(Map<String, dynamic> json) {
    return ServiceAttributeOptionModel(
      id: json['id'] as String,
      attributeId: json['attribute_id'] as String? ?? '',
      optionName: json['option_name'] as String? ?? '',
      priceAdjustment: (json['price_adjustment'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ServiceAttributeModel {
  final String id;
  final String serviceId;
  final String name;
  final String fieldType;
  final bool isRequired;
  final List<ServiceAttributeOptionModel> options;

  const ServiceAttributeModel({
    required this.id,
    required this.serviceId,
    required this.name,
    required this.fieldType,
    this.isRequired = false,
    required this.options,
  });

  bool get hasOptions =>
      fieldType == 'dropdown' ||
      fieldType == 'radio' ||
      fieldType == 'checkbox';

  factory ServiceAttributeModel.fromJson(Map<String, dynamic> json) {
    final rawOptions =
        json['service_attribute_options'] as List<dynamic>? ?? [];
    return ServiceAttributeModel(
      id: json['id'] as String,
      serviceId: json['service_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      fieldType: json['field_type'] as String? ?? 'text',
      isRequired: json['is_required'] as bool? ?? false,
      options: rawOptions
          .map((o) => ServiceAttributeOptionModel.fromJson(
              o as Map<String, dynamic>))
          .toList(),
    );
  }
}
