class ProfileModel {
  final String id;
  final String fullName;
  final String mobileNumber;
  final String? email;
  final String? imageUrl;
  final int totalBookings;
  final int completedBookings;
  final double savedAmount;
  final int favouriteCount;

  const ProfileModel({
    required this.id,
    required this.fullName,
    required this.mobileNumber,
    this.email,
    this.imageUrl,
    this.totalBookings = 0,
    this.completedBookings = 0,
    this.savedAmount = 0,
    this.favouriteCount = 0,
  });

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U';
  }

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'] as String,
      fullName: (json['full_name'] as String?) ?? '',
      mobileNumber: (json['mobile_number'] ?? json['phone'] as String?) ?? '',
      email: json['email'] as String?,
      imageUrl: json['profile_image_url'] as String?,
      totalBookings: (json['total_bookings'] as int?) ?? 0,
      completedBookings: (json['completed_bookings'] as int?) ?? 0,
      savedAmount: ((json['saved_amount'] as num?) ?? 0).toDouble(),
      favouriteCount: (json['favourite_count'] as int?) ?? 0,
    );
  }

  ProfileModel copyWith({
    String? fullName,
    String? email,
    String? imageUrl,
    int? totalBookings,
    int? completedBookings,
    double? savedAmount,
    int? favouriteCount,
  }) {
    return ProfileModel(
      id: id,
      fullName: fullName ?? this.fullName,
      mobileNumber: mobileNumber,
      email: email ?? this.email,
      imageUrl: imageUrl ?? this.imageUrl,
      totalBookings: totalBookings ?? this.totalBookings,
      completedBookings: completedBookings ?? this.completedBookings,
      savedAmount: savedAmount ?? this.savedAmount,
      favouriteCount: favouriteCount ?? this.favouriteCount,
    );
  }
}
