class BookingStatusEvent {
  final String status;
  final String label;
  final DateTime? timestamp;
  final bool isReached;

  const BookingStatusEvent({
    required this.status,
    required this.label,
    this.timestamp,
    bool? isReached,
  }) : isReached = isReached ?? (timestamp != null);

  factory BookingStatusEvent.fromJson(Map<String, dynamic> json) {
    final ts = json['timestamp'] != null
        ? DateTime.parse(json['timestamp'] as String)
        : null;
    return BookingStatusEvent(
      status: json['status'] as String,
      label: json['label'] as String,
      timestamp: ts,
      isReached: (json['is_reached'] as bool?) ?? (ts != null),
    );
  }
}
