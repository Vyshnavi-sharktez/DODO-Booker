class InstaHelpActivity {
  final String id;
  final String modeId;
  final String title;
  final List<String> includedItems;
  final List<String> excludedItems;
  final bool isActive;
  final int sortOrder;

  const InstaHelpActivity({
    required this.id,
    required this.modeId,
    required this.title,
    required this.includedItems,
    required this.excludedItems,
    required this.isActive,
    required this.sortOrder,
  });

  factory InstaHelpActivity.fromMap(Map<String, dynamic> map) => InstaHelpActivity(
        id: map['id'] as String,
        modeId: map['mode_id'] as String,
        title: map['title'] as String,
        includedItems: (map['included_items'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        excludedItems: (map['excluded_items'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        isActive: map['is_active'] as bool? ?? true,
        sortOrder: map['sort_order'] as int? ?? 0,
      );

  InstaHelpActivity copyWith({
    String? title,
    List<String>? includedItems,
    List<String>? excludedItems,
    bool? isActive,
    int? sortOrder,
  }) =>
      InstaHelpActivity(
        id: id,
        modeId: modeId,
        title: title ?? this.title,
        includedItems: includedItems ?? this.includedItems,
        excludedItems: excludedItems ?? this.excludedItems,
        isActive: isActive ?? this.isActive,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}
