class CustomerAddress {
  final String id;
  final String customerId;
  final String addressType;
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String state;
  final String pincode;
  final bool isDefault;
  final double? latitude;
  final double? longitude;

  const CustomerAddress({
    required this.id,
    required this.customerId,
    required this.addressType,
    required this.addressLine1,
    this.addressLine2,
    required this.city,
    required this.state,
    required this.pincode,
    required this.isDefault,
    this.latitude,
    this.longitude,
  });

  factory CustomerAddress.fromMap(Map<String, dynamic> map) {
    return CustomerAddress(
      id: map['id'] as String,
      customerId: map['customer_id'] as String,
      addressType: (map['address_type'] as String?) ?? 'Home',
      addressLine1: (map['address_line_1'] as String?) ?? '',
      addressLine2: map['address_line_2'] as String?,
      city: (map['city'] as String?) ?? '',
      state: (map['state'] as String?) ?? '',
      pincode: (map['pincode'] as String?) ?? '',
      isDefault: (map['is_default'] as bool?) ?? false,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
    );
  }

  String get fullAddress {
    final parts = <String>[
      addressLine1,
      if (addressLine2 != null && addressLine2!.isNotEmpty) addressLine2!,
      city,
      state,
      pincode,
    ].where((p) => p.isNotEmpty).toList();
    return parts.join(', ');
  }
}
