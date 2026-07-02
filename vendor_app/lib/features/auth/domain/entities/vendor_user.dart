class VendorUser {
  const VendorUser({
    required this.id,
    required this.phone,
    this.name,
    this.email,
    this.avatarUrl,
    required this.isActive,
    this.userType = 'vendor',
    this.dodoTeamId,
  });

  final String id;
  final String phone;
  final String? name;
  final String? email;
  final String? avatarUrl;
  final bool isActive;
  // 'vendor' for external vendors, 'dodo_team' for DODO Team supervisors.
  final String userType;
  // Set when userType == 'dodo_team'; matches dodo_team_id on bookings.
  final String? dodoTeamId;

  bool get isDodoTeam => userType == 'dodo_team';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VendorUser && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
