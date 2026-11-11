class InstaHelpMode {
  final String id;
  final String modeType; // 'scheduled' | 'instant'
  final bool isActive;

  const InstaHelpMode({
    required this.id,
    required this.modeType,
    required this.isActive,
  });

  String get displayName => switch (modeType) {
        'scheduled' => 'Scheduled',
        'instant'   => 'Instant',
        'car_wash'  => 'Car Wash',
        _           => modeType,
      };

  factory InstaHelpMode.fromMap(Map<String, dynamic> map) => InstaHelpMode(
        id: map['id'] as String,
        modeType: map['mode_type'] as String,
        isActive: map['is_active'] as bool? ?? true,
      );
}
