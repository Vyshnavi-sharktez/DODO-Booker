import '../../../models/addon_model.dart';

class CartItem {
  final String bookingId;
  final String serviceId;
  final String serviceName;
  final String? imageUrl;
  final double unitPrice;
  final int quantity;

  /// Resolved from catalog_nodes.minimum_order_amount at the time the item was
  /// added (or synced). Null means no minimum applies to this service.
  final double? minimumOrderAmount;

  /// The catalog_node.id of the parent through which the customer navigated
  /// to reach this service.  Null when the path is unknown (e.g. deep-links).
  /// Used by the scoped config resolver for Tax, Loyalty, Scheduling, Commission.
  final String? parentNodeId;

  /// Set when this item represents an AMC (Annual Maintenance Contract) booking.
  /// AMC items bypass minimum order checks and create an amc_contracts record
  /// at checkout time.
  final bool isAmc;
  final String? amcPlanName;
  final String? amcRecurrenceInterval;

  // AMC snapshot fields — snapshotted at add-to-cart time so checkout can
  // write a complete amc_contracts row without re-fetching the plan.
  final String? amcPlanId;
  final double? amcPricePerVisit;
  final int? amcNumVisits;
  final double? amcOriginalTotal;
  final String? amcDiscountType;
  final double? amcDiscountValue;
  final double? amcDiscountAmount;
  final double? amcFinalPrice;
  final String? amcPackageDuration;
  /// Days value for package_duration = 'custom'. Required for custom plans
  /// so the DB trigger can compute expires_at correctly.
  final int? amcPackageDurationValue;
  final String? amcServiceInterval;
  /// Days value for service_interval = 'custom'. Snapshotted for completeness.
  final int? amcServiceIntervalValue;
  final int amcQuantity;
  final bool amcIsRenewal;
  final String? amcPreviousContractId;
  final List<SelectedAddon> addons;
  // Non-null when the service base had a discount at add-to-cart time (for cart display only).
  final double? originalUnitPrice;

  /// Set when this item is a vendor custom service (vendor_service_requests).
  /// customServiceId = vendor_service_requests.id written to booking_items.custom_service_id.
  /// vendorId = the owning vendor, used for direct booking assignment at checkout.
  final String? customServiceId;
  final String? vendorId;

  bool get isCustomService => customServiceId != null;

  const CartItem({
    required this.bookingId,
    required this.serviceId,
    required this.serviceName,
    this.imageUrl,
    required this.unitPrice,
    required this.quantity,
    this.minimumOrderAmount,
    this.parentNodeId,
    this.originalUnitPrice,
    this.customServiceId,
    this.vendorId,
    this.isAmc = false,
    this.amcPlanName,
    this.amcRecurrenceInterval,
    this.amcPlanId,
    this.amcPricePerVisit,
    this.amcNumVisits,
    this.amcOriginalTotal,
    this.amcDiscountType,
    this.amcDiscountValue,
    this.amcDiscountAmount,
    this.amcFinalPrice,
    this.amcPackageDuration,
    this.amcPackageDurationValue,
    this.amcServiceInterval,
    this.amcServiceIntervalValue,
    this.amcQuantity = 1,
    this.amcIsRenewal = false,
    this.amcPreviousContractId,
    this.addons = const [],
  });

  CartItem copyWith({
    int? quantity,
    double? unitPrice,
    double? originalUnitPrice,
    List<SelectedAddon>? addons,
    String? parentNodeId,
    String? customServiceId,
    String? vendorId,
    bool? isAmc,
    String? amcPlanName,
    String? amcRecurrenceInterval,
    String? amcPlanId,
    double? amcPricePerVisit,
    int? amcNumVisits,
    double? amcOriginalTotal,
    String? amcDiscountType,
    double? amcDiscountValue,
    double? amcDiscountAmount,
    double? amcFinalPrice,
    String? amcPackageDuration,
    int? amcPackageDurationValue,
    String? amcServiceInterval,
    int? amcServiceIntervalValue,
    int? amcQuantity,
    bool? amcIsRenewal,
    String? amcPreviousContractId,
  }) =>
      CartItem(
        bookingId: bookingId,
        serviceId: serviceId,
        serviceName: serviceName,
        imageUrl: imageUrl,
        unitPrice: unitPrice ?? this.unitPrice,
        quantity: quantity ?? this.quantity,
        addons: addons ?? this.addons,
        minimumOrderAmount: minimumOrderAmount,
        originalUnitPrice: originalUnitPrice ?? this.originalUnitPrice,
        parentNodeId: parentNodeId ?? this.parentNodeId,
        customServiceId: customServiceId ?? this.customServiceId,
        vendorId: vendorId ?? this.vendorId,
        isAmc: isAmc ?? this.isAmc,
        amcPlanName: amcPlanName ?? this.amcPlanName,
        amcRecurrenceInterval:
            amcRecurrenceInterval ?? this.amcRecurrenceInterval,
        amcPlanId: amcPlanId ?? this.amcPlanId,
        amcPricePerVisit: amcPricePerVisit ?? this.amcPricePerVisit,
        amcNumVisits: amcNumVisits ?? this.amcNumVisits,
        amcOriginalTotal: amcOriginalTotal ?? this.amcOriginalTotal,
        amcDiscountType: amcDiscountType ?? this.amcDiscountType,
        amcDiscountValue: amcDiscountValue ?? this.amcDiscountValue,
        amcDiscountAmount: amcDiscountAmount ?? this.amcDiscountAmount,
        amcFinalPrice: amcFinalPrice ?? this.amcFinalPrice,
        amcPackageDuration: amcPackageDuration ?? this.amcPackageDuration,
        amcPackageDurationValue: amcPackageDurationValue ?? this.amcPackageDurationValue,
        amcServiceInterval: amcServiceInterval ?? this.amcServiceInterval,
        amcServiceIntervalValue: amcServiceIntervalValue ?? this.amcServiceIntervalValue,
        amcQuantity: amcQuantity ?? this.amcQuantity,
        amcIsRenewal: amcIsRenewal ?? this.amcIsRenewal,
        amcPreviousContractId:
            amcPreviousContractId ?? this.amcPreviousContractId,
      );

  double get totalPrice => unitPrice * quantity;

  Map<String, dynamic> toJson() => {
        'bookingId': bookingId,
        'serviceId': serviceId,
        'serviceName': serviceName,
        'imageUrl': imageUrl,
        'unitPrice': unitPrice,
        'quantity': quantity,
        if (minimumOrderAmount != null)
          'minimumOrderAmount': minimumOrderAmount,
        if (originalUnitPrice != null) 'originalUnitPrice': originalUnitPrice,
        if (parentNodeId != null) 'parentNodeId': parentNodeId,
        if (customServiceId != null) 'customServiceId': customServiceId,
        if (vendorId != null) 'vendorId': vendorId,
        if (isAmc) 'isAmc': true,
        if (amcPlanName != null) 'amcPlanName': amcPlanName,
        if (amcRecurrenceInterval != null)
          'amcRecurrenceInterval': amcRecurrenceInterval,
        if (amcPlanId != null) 'amcPlanId': amcPlanId,
        if (amcPricePerVisit != null) 'amcPricePerVisit': amcPricePerVisit,
        if (amcNumVisits != null) 'amcNumVisits': amcNumVisits,
        if (amcOriginalTotal != null) 'amcOriginalTotal': amcOriginalTotal,
        if (amcDiscountType != null) 'amcDiscountType': amcDiscountType,
        if (amcDiscountValue != null) 'amcDiscountValue': amcDiscountValue,
        if (amcDiscountAmount != null) 'amcDiscountAmount': amcDiscountAmount,
        if (amcFinalPrice != null) 'amcFinalPrice': amcFinalPrice,
        if (amcPackageDuration != null) 'amcPackageDuration': amcPackageDuration,
        if (amcPackageDurationValue != null) 'amcPackageDurationValue': amcPackageDurationValue,
        if (amcServiceInterval != null) 'amcServiceInterval': amcServiceInterval,
        if (amcServiceIntervalValue != null) 'amcServiceIntervalValue': amcServiceIntervalValue,
        if (amcQuantity != 1) 'amcQuantity': amcQuantity,
        if (amcIsRenewal) 'amcIsRenewal': true,
        if (amcPreviousContractId != null) 'amcPreviousContractId': amcPreviousContractId,
        if (addons.isNotEmpty)
          'addons': addons.map((a) => a.toJson()).toList(),
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final serviceId = json['serviceId'] as String;
    return CartItem(
        bookingId: json['bookingId'] as String? ?? '${serviceId}_${DateTime.now().millisecondsSinceEpoch}',
        serviceId: serviceId,
        serviceName: json['serviceName'] as String,
        imageUrl: json['imageUrl'] as String?,
        unitPrice: (json['unitPrice'] as num).toDouble(),
        quantity: json['quantity'] as int,
        minimumOrderAmount: (json['minimumOrderAmount'] as num?)?.toDouble(),
        originalUnitPrice: (json['originalUnitPrice'] as num?)?.toDouble(),
        parentNodeId: json['parentNodeId'] as String?,
        customServiceId: json['customServiceId'] as String?,
        vendorId: json['vendorId'] as String?,
        isAmc: json['isAmc'] as bool? ?? false,
        amcPlanName: json['amcPlanName'] as String?,
        amcRecurrenceInterval: json['amcRecurrenceInterval'] as String?,
        amcPlanId: json['amcPlanId'] as String?,
        amcPricePerVisit: (json['amcPricePerVisit'] as num?)?.toDouble(),
        amcNumVisits: (json['amcNumVisits'] as num?)?.toInt(),
        amcOriginalTotal: (json['amcOriginalTotal'] as num?)?.toDouble(),
        amcDiscountType: json['amcDiscountType'] as String?,
        amcDiscountValue: (json['amcDiscountValue'] as num?)?.toDouble(),
        amcDiscountAmount: (json['amcDiscountAmount'] as num?)?.toDouble(),
        amcFinalPrice: (json['amcFinalPrice'] as num?)?.toDouble(),
        amcPackageDuration: json['amcPackageDuration'] as String?,
        amcPackageDurationValue: (json['amcPackageDurationValue'] as num?)?.toInt(),
        amcServiceInterval: json['amcServiceInterval'] as String?,
        amcServiceIntervalValue: (json['amcServiceIntervalValue'] as num?)?.toInt(),
        amcQuantity: (json['amcQuantity'] as num?)?.toInt() ?? 1,
        amcIsRenewal: json['amcIsRenewal'] as bool? ?? false,
        amcPreviousContractId: json['amcPreviousContractId'] as String?,
        addons: (json['addons'] as List<dynamic>?)
                ?.map((e) => SelectedAddon.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
  }
}
