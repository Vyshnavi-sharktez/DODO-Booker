class PreferredVendorModel {
  final String id;
  final String businessName;
  final double? rating;
  final double preferredVendorFee;

  const PreferredVendorModel({
    required this.id,
    required this.businessName,
    this.rating,
    required this.preferredVendorFee,
  });

  factory PreferredVendorModel.fromMap(Map<String, dynamic> map) {
    return PreferredVendorModel(
      id: map['id'] as String,
      businessName: map['business_name'] as String? ?? '',
      rating: (map['rating'] as num?)?.toDouble(),
      preferredVendorFee:
          (map['preferred_vendor_fee'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
