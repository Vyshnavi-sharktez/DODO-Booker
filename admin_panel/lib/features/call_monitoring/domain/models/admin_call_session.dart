class AdminCallSession {
  final String id;
  final String bookingId;
  final String? bookingNumber;
  final String callerId;
  final String? callerName;
  final String calleeId;
  final String? calleeName;
  final String callerRole; // 'customer' or 'vendor'
  final String virtualNumber; // e.g. '+91-80000-DODO1'
  final String status; // 'initiated', 'ringing', 'connected', 'ended', 'missed', 'failed'
  final DateTime initiatedAt;
  final DateTime? endedAt;
  final int storedDurationSeconds;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AdminCallSession({
    required this.id,
    required this.bookingId,
    this.bookingNumber,
    required this.callerId,
    this.callerName,
    required this.calleeId,
    this.calleeName,
    required this.callerRole,
    required this.virtualNumber,
    required this.status,
    required this.initiatedAt,
    this.endedAt,
    this.storedDurationSeconds = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isInitiated => status == 'initiated';
  bool get isRinging => status == 'ringing';
  bool get isConnected => status == 'connected';
  bool get isEnded => status == 'ended';
  bool get isMissed => status == 'missed';
  bool get isFailed => status == 'failed';

  int get durationSeconds {
    if (storedDurationSeconds > 0) return storedDurationSeconds;
    if (endedAt != null) {
      return endedAt!.difference(initiatedAt).inSeconds;
    } else if (isConnected) {
      return DateTime.now().difference(initiatedAt).inSeconds;
    }
    return 0;
  }

  String get durationFormatted {
    final secs = durationSeconds;
    final minutes = (secs ~/ 60).toString().padLeft(2, '0');
    final seconds = (secs % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get displayBookingNumber {
    if (bookingNumber != null && bookingNumber!.isNotEmpty) {
      return bookingNumber!;
    }
    if (bookingId.length >= 8) {
      return 'BK-${bookingId.substring(0, 8).toUpperCase()}';
    }
    return bookingId;
  }

  factory AdminCallSession.fromMap(Map<String, dynamic> map) {
    final bookingObj = map['bookings'] as Map<String, dynamic>?;
    final bookingNum = bookingObj?['booking_number'] as String?;

    return AdminCallSession(
      id: map['id'] as String,
      bookingId: map['booking_id'] as String,
      bookingNumber: bookingNum,
      callerId: map['caller_id'] as String,
      calleeId: map['callee_id'] as String,
      callerRole: map['caller_role'] as String? ?? 'customer',
      virtualNumber: map['virtual_number'] as String? ?? '+91-80000-DODO1',
      status: map['status'] as String? ?? 'initiated',
      initiatedAt: map['initiated_at'] != null
          ? DateTime.tryParse(map['initiated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      endedAt: map['ended_at'] != null
          ? DateTime.tryParse(map['ended_at'] as String)
          : null,
      storedDurationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
