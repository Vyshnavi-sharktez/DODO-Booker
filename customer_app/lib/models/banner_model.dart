class BannerModel {
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? actionLabel;
  final String? redirectType;
  final String? redirectId;
  final bool isActive;

  const BannerModel({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.actionLabel,
    this.redirectType,
    this.redirectId,
    this.isActive = true,
  });

  factory BannerModel.fromJson(Map<String, dynamic> json) {
    return BannerModel(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String?,
      imageUrl: json['image_url'] as String?,
      actionLabel: json['action_label'] as String?,
      redirectType: json['redirect_type'] as String?,
      redirectId: json['redirect_id'] as String?,
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}
