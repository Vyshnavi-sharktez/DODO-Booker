class WhatsappProviderConfig {
  final String provider;
  final bool isEnabled;
  final String providerName;
  final String apiUrl;
  final Map<String, dynamic> extraConfig;

  const WhatsappProviderConfig({
    required this.provider,
    required this.isEnabled,
    required this.providerName,
    required this.apiUrl,
    required this.extraConfig,
  });

  factory WhatsappProviderConfig.empty(String provider) => WhatsappProviderConfig(
        provider: provider,
        isEnabled: false,
        providerName: '',
        apiUrl: '',
        extraConfig: const {},
      );

  factory WhatsappProviderConfig.fromJson(Map<String, dynamic> json) =>
      WhatsappProviderConfig(
        provider: json['provider'] as String,
        isEnabled: (json['is_enabled'] as bool?) ?? false,
        providerName: (json['provider_name'] as String?) ?? '',
        apiUrl: (json['api_url'] as String?) ?? '',
        extraConfig:
            (json['extra_config'] as Map<String, dynamic>?) ?? const {},
      );

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'is_enabled': isEnabled,
        'provider_name': providerName,
        'api_url': apiUrl,
        'extra_config': extraConfig,
      };

  WhatsappProviderConfig copyWith({
    bool? isEnabled,
    String? providerName,
    String? apiUrl,
    Map<String, dynamic>? extraConfig,
  }) =>
      WhatsappProviderConfig(
        provider: provider,
        isEnabled: isEnabled ?? this.isEnabled,
        providerName: providerName ?? this.providerName,
        apiUrl: apiUrl ?? this.apiUrl,
        extraConfig: extraConfig ?? this.extraConfig,
      );
}
