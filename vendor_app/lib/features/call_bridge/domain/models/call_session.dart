class CallSession {
  final String id;
  final String bookingId;
  final String callerId;
  final String calleeId;
  final String callerRole; // 'customer' or 'vendor'
  final String virtualNumber; // Exotel ExoPhone
  final String status; // 'initiated', 'ringing', 'connected', 'ended', 'missed', 'failed'
  final DateTime initiatedAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final String? exotelCallSid;
  final String? recordingUrl;
  final String recordingStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CallSession({
    required this.id,
    required this.bookingId,
    required this.callerId,
    required this.calleeId,
    required this.callerRole,
    this.virtualNumber = '',
    this.status = 'initiated',
    required this.initiatedAt,
    this.endedAt,
    this.durationSeconds = 0,
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
  bool get isTerminal => isEnded || isMissed || isFailed;

  int get calculatedDurationSeconds {
    if (durationSeconds > 0) return durationSeconds;
    if (endedAt != null) {
      return endedAt!.difference(initiatedAt).inSeconds;
    } else if (isConnected) {
      return DateTime.now().difference(initiatedAt).inSeconds;
    }
    return 0;
  }

  String get durationFormatted {
    final secs = calculatedDurationSeconds;
    final minutes = (secs ~/ 60).toString().padLeft(2, '0');
    final seconds = (secs % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  CallSession copyWith({
    String? id,
    String? bookingId,
    String? callerId,
    String? calleeId,
    String? callerRole,
    String? virtualNumber,
    String? status,
    DateTime? initiatedAt,
    DateTime? endedAt,
    int? durationSeconds,
    String? exotelCallSid,
    String? recordingUrl,
    String? recordingStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CallSession(
      id: id ?? this.id,
      bookingId: bookingId ?? this.bookingId,
      callerId: callerId ?? this.callerId,
      calleeId: calleeId ?? this.calleeId,
      callerRole: callerRole ?? this.callerRole,
      virtualNumber: virtualNumber ?? this.virtualNumber,
      status: status ?? this.status,
      initiatedAt: initiatedAt ?? this.initiatedAt,
      endedAt: endedAt ?? this.endedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      exotelCallSid: exotelCallSid ?? this.exotelCallSid,
      recordingUrl: recordingUrl ?? this.recordingUrl,
      recordingStatus: recordingStatus ?? this.recordingStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory CallSession.fromMap(Map<String, dynamic> map) {
    return CallSession(
      id: map['id'] as String,
      bookingId: map['booking_id'] as String,
      callerId: map['caller_id'] as String,
      calleeId: map['callee_id'] as String,
      callerRole: map['caller_role'] as String? ?? 'vendor',
      virtualNumber: map['virtual_number'] as String? ?? '',
      status: map['status'] as String? ?? 'initiated',
      initiatedAt: map['initiated_at'] != null
          ? DateTime.tryParse(map['initiated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      endedAt: map['ended_at'] != null
          ? DateTime.tryParse(map['ended_at'] as String)
          : null,
      durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      exotelCallSid: map['exotel_call_sid'] as String?,
      recordingUrl: map['recording_url'] as String?,
      recordingStatus: map['recording_status'] as String? ?? 'none',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'booking_id': bookingId,
      'caller_id': callerId,
      'callee_id': calleeId,
      'caller_role': callerRole,
      'virtual_number': virtualNumber,
      'status': status,
      'initiated_at': initiatedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'duration_seconds': durationSeconds,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
