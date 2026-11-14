class BotConfig {
  final String id;
  final bool isEnabled;
  final String model;
  final String systemPrompt;
  final int maxHistory;
  final String handoffTriggers;
  final String closeTriggers;
  final String webhookUrl;
  final String? botAdminId;
  final int messageRetentionDays;
  final int conversationRetentionDays;
  final int handoffTimeoutMinutes;
  final String handoffTimeoutMessage;

  const BotConfig({
    required this.id,
    required this.isEnabled,
    required this.model,
    required this.systemPrompt,
    required this.maxHistory,
    required this.handoffTriggers,
    required this.closeTriggers,
    required this.webhookUrl,
    this.botAdminId,
    this.messageRetentionDays = 90,
    this.conversationRetentionDays = 365,
    this.handoffTimeoutMinutes = 30,
    this.handoffTimeoutMessage =
        "Our support team is currently busy. We'll get back to you as soon as possible. Thank you for your patience!",
  });

  factory BotConfig.fromJson(Map<String, dynamic> json) => BotConfig(
        id: json['id'] as String,
        isEnabled: (json['is_enabled'] as bool?) ?? false,
        model: (json['model'] as String?) ?? 'gemini-2.5-flash',
        systemPrompt: (json['system_prompt'] as String?) ?? '',
        maxHistory: (json['max_history'] as int?) ?? 10,
        handoffTriggers: (json['handoff_triggers'] as String?) ?? '',
        closeTriggers: (json['close_triggers'] as String?) ?? '',
        webhookUrl: (json['webhook_url'] as String?) ?? '',
        botAdminId: json['bot_admin_id'] as String?,
        messageRetentionDays: (json['message_retention_days'] as int?) ?? 90,
        conversationRetentionDays: (json['conversation_retention_days'] as int?) ?? 365,
        handoffTimeoutMinutes: (json['handoff_timeout_minutes'] as int?) ?? 30,
        handoffTimeoutMessage: (json['handoff_timeout_message'] as String?) ??
            "Our support team is currently busy. We'll get back to you as soon as possible. Thank you for your patience!",
      );

  Map<String, dynamic> toJson() => {
        'is_enabled': isEnabled,
        'model': model,
        'system_prompt': systemPrompt,
        'max_history': maxHistory,
        'handoff_triggers': handoffTriggers,
        'close_triggers': closeTriggers,
        'webhook_url': webhookUrl,
        'message_retention_days': messageRetentionDays,
        'conversation_retention_days': conversationRetentionDays,
        'handoff_timeout_minutes': handoffTimeoutMinutes,
        'handoff_timeout_message': handoffTimeoutMessage,
      };

  BotConfig copyWith({
    bool? isEnabled,
    String? model,
    String? systemPrompt,
    int? maxHistory,
    String? handoffTriggers,
    String? closeTriggers,
    String? webhookUrl,
    int? messageRetentionDays,
    int? conversationRetentionDays,
    int? handoffTimeoutMinutes,
    String? handoffTimeoutMessage,
  }) =>
      BotConfig(
        id: id,
        isEnabled: isEnabled ?? this.isEnabled,
        model: model ?? this.model,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        maxHistory: maxHistory ?? this.maxHistory,
        handoffTriggers: handoffTriggers ?? this.handoffTriggers,
        closeTriggers: closeTriggers ?? this.closeTriggers,
        webhookUrl: webhookUrl ?? this.webhookUrl,
        botAdminId: botAdminId,
        messageRetentionDays: messageRetentionDays ?? this.messageRetentionDays,
        conversationRetentionDays: conversationRetentionDays ?? this.conversationRetentionDays,
        handoffTimeoutMinutes: handoffTimeoutMinutes ?? this.handoffTimeoutMinutes,
        handoffTimeoutMessage: handoffTimeoutMessage ?? this.handoffTimeoutMessage,
      );
}
