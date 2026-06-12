class BookingStatusEvent {
  final String status;
  final String label;
  final DateTime? timestamp;

  const BookingStatusEvent({
    required this.status,
    required this.label,
    this.timestamp,
  });

  bool get isReached => timestamp != null;

  factory BookingStatusEvent.fromJson(Map<String, dynamic> json) {
    return BookingStatusEvent(
      status: json['status'] as String,
      label: json['label'] as String,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }
}
