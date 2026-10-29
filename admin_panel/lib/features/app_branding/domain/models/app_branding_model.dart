class AppBrandingModel {
  const AppBrandingModel({
    required this.appId,
    required this.displayName,
    this.iconUrl,
    this.updatedAt,
  });

  final String appId;
  final String displayName;
  final String? iconUrl;
  final DateTime? updatedAt;

  bool get hasIcon => iconUrl != null && iconUrl!.isNotEmpty;

  factory AppBrandingModel.fromMap(Map<String, dynamic> map) =>
      AppBrandingModel(
        appId: map['app_id'] as String,
        displayName: map['display_name'] as String,
        iconUrl: map['icon_url'] as String?,
        updatedAt: map['updated_at'] != null
            ? DateTime.tryParse(map['updated_at'] as String)
            : null,
      );

  AppBrandingModel copyWith({String? iconUrl, bool clearIcon = false}) =>
      AppBrandingModel(
        appId: appId,
        displayName: displayName,
        iconUrl: clearIcon ? null : (iconUrl ?? this.iconUrl),
        updatedAt: updatedAt,
      );
}
