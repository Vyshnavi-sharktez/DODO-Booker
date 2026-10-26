class DeletedBooking {
  final String bookingId;
  final String bookingNumber;
  final DateTime deletedAt;
  final String? deletedBy;
  final String? deletedByName;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? status;
  final double? totalAmount;
  final DateTime? serviceDate;
  final String? address;
  final List<String> serviceNames;
  final int itemsCount;

  const DeletedBooking({
    required this.bookingId,
    required this.bookingNumber,
    required this.deletedAt,
    this.deletedBy,
    this.deletedByName,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.status,
    this.totalAmount,
    this.serviceDate,
    this.address,
    required this.serviceNames,
    required this.itemsCount,
  });

  factory DeletedBooking.fromMap(Map<String, dynamic> map) {
    List<String> names = [];
    final rawNames = map['service_names'];
    if (rawNames is List) {
      names = rawNames.whereType<String>().where((s) => s.isNotEmpty).toList();
    }

    DateTime? serviceDate;
    final sdRaw = map['service_date'];
    if (sdRaw != null) {
      serviceDate = sdRaw is DateTime ? sdRaw : DateTime.tryParse(sdRaw.toString());
    }

    return DeletedBooking(
      bookingId: map['booking_id'] as String,
      bookingNumber: (map['booking_number'] as String?) ?? '',
      deletedAt: map['deleted_at'] is DateTime
          ? map['deleted_at'] as DateTime
          : DateTime.parse(map['deleted_at'] as String),
      deletedBy: map['deleted_by'] as String?,
      deletedByName: map['deleted_by_name'] as String?,
      customerId: map['customer_id'] as String?,
      customerName: map['customer_name'] as String?,
      customerPhone: map['customer_phone'] as String?,
      status: map['status'] as String?,
      totalAmount: (map['total_amount'] as num?)?.toDouble(),
      serviceDate: serviceDate,
      address: map['address'] as String?,
      serviceNames: names,
      itemsCount: (map['items_count'] as num?)?.toInt() ?? 0,
    );
  }

  // ── Retention / expiry helpers ─────────────────────────────────────────────

  DateTime expiresAt({required int retentionValue, required String retentionUnit}) {
    return _addDuration(deletedAt, retentionValue, retentionUnit);
  }

  bool isExpired({required int retentionValue, required String retentionUnit}) {
    return DateTime.now().isAfter(expiresAt(retentionValue: retentionValue, retentionUnit: retentionUnit));
  }

  Duration timeUntilExpiry({required int retentionValue, required String retentionUnit}) {
    return expiresAt(retentionValue: retentionValue, retentionUnit: retentionUnit)
        .difference(DateTime.now());
  }

  static DateTime _addDuration(DateTime from, int value, String unit) {
    switch (unit) {
      case 'weeks':
        return from.add(Duration(days: value * 7));
      case 'months':
        // Calendar-month arithmetic matching PostgreSQL interval behaviour
        final totalMonths = from.month + value;
        final year = from.year + ((totalMonths - 1) ~/ 12);
        final month = ((totalMonths - 1) % 12) + 1;
        final maxDay = DateTime(year, month + 1, 0).day;
        return DateTime(
          year, month, from.day.clamp(1, maxDay),
          from.hour, from.minute, from.second, from.millisecond,
        );
      default: // 'days'
        return from.add(Duration(days: value));
    }
  }

  String get displayName => customerName?.isNotEmpty == true ? customerName! : 'Unknown Customer';

  String get serviceSummary {
    if (serviceNames.isEmpty) return itemsCount > 0 ? '$itemsCount item(s)' : '—';
    if (serviceNames.length == 1) return serviceNames.first;
    return '${serviceNames.first} +${serviceNames.length - 1}';
  }
}
