class PaymentGatewayConfig {
  final String gateway;
  final bool isEnabled;
  final String mode;
  final String displayName;
  final String publicKey;
  final Map<String, dynamic> extraConfig;

  const PaymentGatewayConfig({
    required this.gateway,
    required this.isEnabled,
    required this.mode,
    required this.displayName,
    required this.publicKey,
    required this.extraConfig,
  });

  factory PaymentGatewayConfig.empty(String gateway) => PaymentGatewayConfig(
        gateway: gateway,
        isEnabled: false,
        mode: 'test',
        displayName: '',
        publicKey: '',
        extraConfig: const {},
      );

  factory PaymentGatewayConfig.fromJson(Map<String, dynamic> json) =>
      PaymentGatewayConfig(
        gateway: json['gateway'] as String,
        isEnabled: (json['is_enabled'] as bool?) ?? false,
        mode: (json['mode'] as String?) ?? 'test',
        displayName: (json['display_name'] as String?) ?? '',
        publicKey: (json['public_key'] as String?) ?? '',
        extraConfig:
            (json['extra_config'] as Map<String, dynamic>?) ?? const {},
      );

  Map<String, dynamic> toJson() => {
        'gateway': gateway,
        'is_enabled': isEnabled,
        'mode': mode,
        'display_name': displayName,
        'public_key': publicKey,
        'extra_config': extraConfig,
      };

  PaymentGatewayConfig copyWith({
    bool? isEnabled,
    String? mode,
    String? displayName,
    String? publicKey,
    Map<String, dynamic>? extraConfig,
  }) =>
      PaymentGatewayConfig(
        gateway: gateway,
        isEnabled: isEnabled ?? this.isEnabled,
        mode: mode ?? this.mode,
        displayName: displayName ?? this.displayName,
        publicKey: publicKey ?? this.publicKey,
        extraConfig: extraConfig ?? this.extraConfig,
      );
}
