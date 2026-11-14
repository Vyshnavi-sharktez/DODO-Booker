class InstaHelpMode {
  final String id;
  final String modeType; // 'scheduled' | 'instant' | 'car_wash'
  final bool isActive;
  final String? vendorId;
  final int sortOrder;

  const InstaHelpMode({
    required this.id,
    required this.modeType,
    required this.isActive,
    this.vendorId,
    this.sortOrder = 0,
  });

  String get displayName {
    switch (modeType) {
      case 'scheduled': return 'Scheduled';
      case 'instant':   return 'Instant';
      case 'car_wash':  return 'Car Wash';
      default:          return modeType;
    }
  }

  InstaHelpMode copyWith({bool? isActive, int? sortOrder}) => InstaHelpMode(
        id: id,
        modeType: modeType,
        isActive: isActive ?? this.isActive,
        vendorId: vendorId,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  factory InstaHelpMode.fromMap(Map<String, dynamic> map) => InstaHelpMode(
        id: map['id'] as String,
        modeType: map['mode_type'] as String,
        isActive: map['is_active'] as bool? ?? true,
        vendorId: map['vendor_id'] as String?,
        sortOrder: map['sort_order'] as int? ?? 0,
      );
}
