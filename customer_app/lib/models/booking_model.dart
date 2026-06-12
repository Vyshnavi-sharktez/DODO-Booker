class BookingModel {
  final String id;
  final String serviceId;
  final String serviceName;
  final String addressId;
  final String addressLabel;
  final DateTime scheduledDate;
  final String timeSlot;
  final double baseAmount;
  final double taxAmount;
  final double totalAmount;
  final String status;
  final DateTime createdAt;

  const BookingModel({
    required this.id,
    required this.serviceId,
    required this.serviceName,
    required this.addressId,
    required this.addressLabel,
    required this.scheduledDate,
    required this.timeSlot,
    required this.baseAmount,
    required this.taxAmount,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
  });

  factory BookingModel.fromJson(Map<String, dynamic> json) {
    // DB columns: id, booking_number, customer_id, vendor_id, service_date,
    //             status, subtotal, discount_amount, total_amount, address, notes
    return BookingModel(
      id: json['id'] as String,
      // DB has no service_id; fall back to booking_number or id
      serviceId: (json['service_id'] as String?) ?? (json['booking_number'] as String?) ?? json['id'] as String,
      // DB has no service_name; fall back to notes or empty
      serviceName: (json['service_name'] as String?) ?? (json['booking_number'] as String?) ?? '',
      // DB has no address_id; fall back to empty
      addressId: (json['address_id'] as String?) ?? '',
      // DB: address is a text field
      addressLabel: (json['address_label'] as String?) ?? (json['address'] as String?) ?? '',
      // DB column: service_date; mock key: scheduled_date
      scheduledDate: DateTime.parse(
        ((json['scheduled_date'] ?? json['service_date']) as String?) ?? DateTime.now().toIso8601String(),
      ),
      // DB has no time_slot column
      timeSlot: (json['time_slot'] as String?) ?? '',
      // DB column: subtotal; mock key: base_amount
      baseAmount: ((json['base_amount'] ?? json['subtotal']) as num?)?.toDouble() ?? 0.0,
      // DB has no tax_amount; discount_amount is a separate concept
      taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
