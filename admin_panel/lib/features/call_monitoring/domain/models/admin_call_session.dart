class AdminCallSession {
  final String id;
  final String bookingId;
  final String? bookingNumber;
  final String callerId;
  final String? callerName;
  final String calleeId;
  final String? calleeName;
  final String callerRole; // 'customer' or 'vendor'
  final String virtualNumber; // Exotel ExoPhone
  final String status; // 'initiated', 'ringing', 'connected', 'ended', 'missed', 'failed'
  final DateTime initiatedAt;
  final DateTime? endedAt;
  final int storedDurationSeconds;
  final String? exotelCallSid;
  final String? recordingUrl;
  final String recordingStatus; // 'none', 'pending', 'available', 'failed'
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
    this.exotelCallSid,
    this.recordingUrl,
    this.recordingStatus = 'none',
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
      return 'DODO${bookingId.substring(0, 8).toUpperCase()}';
    }
    return bookingId;
  }

  factory AdminCallSession.fromMap(Map<String, dynamic> map) {
    final bookingObj = map['bookings'] as Map<String, dynamic>?;
    final bookingNum = bookingObj?['booking_number'] as String?;

    // Recording URLs are stored in call_session_recordings (admin-only table)
    // and joined here.  Participants never see the URL via call_sessions directly.
    final recordingRows =
        map['call_session_recordings'] as List<dynamic>? ?? [];
    final recordingRow = recordingRows.isNotEmpty
        ? recordingRows.first as Map<String, dynamic>
        : null;
    final recUrl = recordingRow?['recording_url'] as String?;

    return AdminCallSession(
      id: map['id'] as String,
      bookingId: map['booking_id'] as String,
      bookingNumber: bookingNum,
      callerId: map['caller_id'] as String,
      calleeId: map['callee_id'] as String,
      callerRole: map['caller_role'] as String? ?? 'customer',
      virtualNumber: map['virtual_number'] as String? ?? '',
      status: map['status'] as String? ?? 'initiated',
      initiatedAt: map['initiated_at'] != null
          ? DateTime.tryParse(map['initiated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      endedAt: map['ended_at'] != null
          ? DateTime.tryParse(map['ended_at'] as String)
          : null,
      storedDurationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      exotelCallSid: map['exotel_call_sid'] as String?,
      recordingUrl: recUrl,
      recordingStatus: map['recording_status'] as String? ?? 'none',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
