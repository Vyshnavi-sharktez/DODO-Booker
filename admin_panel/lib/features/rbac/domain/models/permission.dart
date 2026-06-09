class Permission {
  final String id;
  final String name;
  final String? description;
  final String module;

  const Permission({
    required this.id,
    required this.name,
    this.description,
    required this.module,
  });

  factory Permission.fromMap(Map<String, dynamic> map) {
    final nameStr = map['name'] as String? ?? '';
    // Derive module from the name prefix (e.g. "booking.view" → "BOOKING").
    final derivedModule = nameStr.contains('.')
        ? nameStr.split('.').first.toUpperCase()
        : 'GENERAL';

    return Permission(
      id: map['id'] as String,
      name: nameStr,
      description: map['description'] as String?,
      module: derivedModule,
    );
  }
}
