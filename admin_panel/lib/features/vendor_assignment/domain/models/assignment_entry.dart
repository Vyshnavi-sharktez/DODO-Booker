class AssignmentEntry {
  final String bookingId;
  final String bookingNumber;
  final String? previousVendorId;
  final String previousVendorName;
  final String newVendorId;
  final String newVendorName;
  final DateTime assignedAt;
  final String adminName;

  const AssignmentEntry({
    required this.bookingId,
    required this.bookingNumber,
    required this.previousVendorId,
    required this.previousVendorName,
    required this.newVendorId,
    required this.newVendorName,
    required this.assignedAt,
    required this.adminName,
  });

  bool get isReassignment => previousVendorId != null && previousVendorId!.isNotEmpty;
}
