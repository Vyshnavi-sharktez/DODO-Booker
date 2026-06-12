class AddressModel {
  final String id;
  final String label;
  final String line1;
  final String? line2;
  final String city;
  final String state;
  final String pincode;
  final bool isDefault;

  const AddressModel({
    required this.id,
    required this.label,
    required this.line1,
    this.line2,
    required this.city,
    required this.state,
    required this.pincode,
    this.isDefault = false,
  });

  String get fullAddress {
    final parts = [line1, ?line2, city, state, pincode];
    return parts.join(', ');
  }

  String get shortAddress => '$line1, $city';

  factory AddressModel.fromJson(Map<String, dynamic> json) {
    return AddressModel(
      id: json['id'] as String,
      label: json['address_type'] as String,
      line1: json['address_line_1'] as String,
      line2: json['address_line_2'] as String?,
      city: json['city'] as String,
      state: json['state'] as String,
      pincode: json['pincode'] as String,
      isDefault: (json['is_default'] as bool?) ?? false,
    );
  }
}
