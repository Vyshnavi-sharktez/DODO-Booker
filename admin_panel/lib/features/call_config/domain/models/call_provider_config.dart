class CallProviderConfig {
  final String id;
  final String provider;
  final bool isEnabled;
  final String? accountSid;
  final String? exophone;
  final bool recordCalls;
  final int callTimeoutSeconds;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CallProviderConfig({
    required this.id,
    required this.provider,
    required this.isEnabled,
    this.accountSid,
    this.exophone,
    required this.recordCalls,
    required this.callTimeoutSeconds,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isConfigured =>
      accountSid != null &&
      accountSid!.isNotEmpty &&
      exophone != null &&
      exophone!.isNotEmpty;

  factory CallProviderConfig.fromMap(Map<String, dynamic> map) {
    return CallProviderConfig(
      id: map['id'] as String,
      provider: map['provider'] as String? ?? 'exotel',
      isEnabled: map['is_enabled'] as bool? ?? false,
      accountSid: map['account_sid'] as String?,
      exophone: map['exophone'] as String?,
      recordCalls: map['record_calls'] as bool? ?? true,
      callTimeoutSeconds: (map['call_timeout_seconds'] as num?)?.toInt() ?? 30,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
