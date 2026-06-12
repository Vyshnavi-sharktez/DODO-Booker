class VendorUser {
  const VendorUser({
    required this.id,
    required this.phone,
    this.name,
    this.email,
    this.avatarUrl,
    required this.isActive,
  });

  final String id;
  final String phone;
  final String? name;
  final String? email;
  final String? avatarUrl;
  final bool isActive;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VendorUser && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
