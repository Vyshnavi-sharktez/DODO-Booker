class SmsProviderConfig {
  final String id;
  final String provider;
  final bool isEnabled;
  final String providerName;
  final String apiUrl;
  final Map<String, dynamic> extraConfig;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SmsProviderConfig({
    required this.id,
    required this.provider,
    required this.isEnabled,
    required this.providerName,
    required this.apiUrl,
    required this.extraConfig,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SmsProviderConfig.empty(String provider) => SmsProviderConfig(
        id: '',
        provider: provider,
        isEnabled: false,
        providerName: '',
        apiUrl: '',
        extraConfig: const {},
        createdAt: DateTime(0),
        updatedAt: DateTime(0),
      );

  factory SmsProviderConfig.fromJson(Map<String, dynamic> json) =>
      SmsProviderConfig(
        id: json['id'] as String? ?? '',
        provider: json['provider'] as String,
        isEnabled: json['is_enabled'] as bool? ?? false,
        providerName: json['provider_name'] as String? ?? '',
        apiUrl: json['api_url'] as String? ?? '',
        extraConfig:
            (json['extra_config'] as Map<String, dynamic>?) ?? const {},
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : DateTime(0),
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String)
            : DateTime(0),
      );

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'provider': provider,
        'is_enabled': isEnabled,
        'provider_name': providerName,
        'api_url': apiUrl,
        'extra_config': extraConfig,
      };

  SmsProviderConfig copyWith({
    String? id,
    String? provider,
    bool? isEnabled,
    String? providerName,
    String? apiUrl,
    Map<String, dynamic>? extraConfig,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      SmsProviderConfig(
        id: id ?? this.id,
        provider: provider ?? this.provider,
        isEnabled: isEnabled ?? this.isEnabled,
        providerName: providerName ?? this.providerName,
        apiUrl: apiUrl ?? this.apiUrl,
        extraConfig: extraConfig ?? this.extraConfig,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
