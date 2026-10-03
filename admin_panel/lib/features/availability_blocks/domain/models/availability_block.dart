class AvailabilityBlock {
  final String id;
  final String scope; // 'global' | 'category' | 'service' | 'vendor'
  final String? nodeId;
  final String? vendorId;
  final DateTime startDate;
  final DateTime endDate;
  final List<String>? blockedSlots; // null = full-day block
  final String? reason;
  final bool isEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AvailabilityBlock({
    required this.id,
    required this.scope,
    this.nodeId,
    this.vendorId,
    required this.startDate,
    required this.endDate,
    this.blockedSlots,
    this.reason,
    required this.isEnabled,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isFullDay => blockedSlots == null;

  factory AvailabilityBlock.fromMap(Map<String, dynamic> m) {
    List<String>? slots;
    if (m['blocked_slots'] != null) {
      slots = (m['blocked_slots'] as List).cast<String>();
    }
    return AvailabilityBlock(
      id: m['id'] as String,
      scope: m['scope'] as String,
      nodeId: m['node_id'] as String?,
      vendorId: m['vendor_id'] as String?,
      startDate: DateTime.parse(m['start_date'] as String),
      endDate: DateTime.parse(m['end_date'] as String),
      blockedSlots: slots,
      reason: m['reason'] as String?,
      isEnabled: (m['is_enabled'] as bool?) ?? true,
      createdAt: DateTime.parse(m['created_at'] as String),
      updatedAt: DateTime.parse(m['updated_at'] as String),
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'scope': scope,
        'node_id': nodeId,
        'vendor_id': vendorId,
        'start_date': _fmtDate(startDate),
        'end_date': _fmtDate(endDate),
        'blocked_slots': blockedSlots,
        'reason': reason,
        'is_enabled': isEnabled,
      };

  Map<String, dynamic> toUpdateMap() => {
        'scope': scope,
        'node_id': nodeId,
        'vendor_id': vendorId,
        'start_date': _fmtDate(startDate),
        'end_date': _fmtDate(endDate),
        'blocked_slots': blockedSlots,
        'reason': reason,
        'is_enabled': isEnabled,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  AvailabilityBlock copyWith({
    String? id,
    String? scope,
    Object? nodeId = _sentinel,
    Object? vendorId = _sentinel,
    DateTime? startDate,
    DateTime? endDate,
    Object? blockedSlots = _sentinel,
    Object? reason = _sentinel,
    bool? isEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AvailabilityBlock(
      id: id ?? this.id,
      scope: scope ?? this.scope,
      nodeId: nodeId == _sentinel ? this.nodeId : nodeId as String?,
      vendorId: vendorId == _sentinel ? this.vendorId : vendorId as String?,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      blockedSlots: blockedSlots == _sentinel
          ? this.blockedSlots
          : blockedSlots as List<String>?,
      reason: reason == _sentinel ? this.reason : reason as String?,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

const _sentinel = Object();
