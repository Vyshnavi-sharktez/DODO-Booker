class InstaHelpActivityModel {
  final String id;
  final String title;
  final List<String> includedItems;
  final List<String> excludedItems;
  final int sortOrder;

  const InstaHelpActivityModel({
    required this.id,
    required this.title,
    required this.includedItems,
    required this.excludedItems,
    required this.sortOrder,
  });

  factory InstaHelpActivityModel.fromMap(Map<String, dynamic> map) =>
      InstaHelpActivityModel(
        id: map['id'] as String,
        title: (map['title'] ?? '').toString(),
        includedItems: (map['included_items'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList(),
        excludedItems: (map['excluded_items'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList(),
        sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      );
}
