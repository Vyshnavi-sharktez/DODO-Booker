class AddOnModel {
  final String id;
  final String name;
  final String? description;
  final double price;
  final String discountType;
  final double discountValue;
  final bool isGlobal;

  const AddOnModel({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    this.discountType = 'percentage',
    this.discountValue = 0,
    this.isGlobal = false,
  });

  double get discountAmount => discountType == 'percentage'
      ? price * discountValue / 100
      : discountValue;

  double get finalPrice =>
      (price - discountAmount).clamp(0.0, double.infinity);

  bool get hasDiscount => discountValue > 0;

  factory AddOnModel.fromJson(Map<String, dynamic> json) {
    return AddOnModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      price: (json['price'] as num).toDouble(),
      discountType: (json['discount_type'] as String?) ?? 'percentage',
      discountValue: (json['discount_value'] as num?)?.toDouble() ?? 0,
      isGlobal: (json['is_global'] as bool?) ?? false,
    );
  }
}

/// An add-on the customer has chosen for a booking, with the price locked at
/// selection time so it survives admin edits.
class SelectedAddon {
  final String addonId;
  final String addonName;
  final double addonPrice;
  // Non-null when the addon had a discount at selection time (for cart display only).
  final double? originalAddonPrice;
  final int quantity;

  const SelectedAddon({
    required this.addonId,
    required this.addonName,
    required this.addonPrice,
    this.originalAddonPrice,
    this.quantity = 1,
  });

  SelectedAddon copyWith({int? quantity}) => SelectedAddon(
        addonId: addonId,
        addonName: addonName,
        addonPrice: addonPrice,
        originalAddonPrice: originalAddonPrice,
        quantity: quantity ?? this.quantity,
      );

  Map<String, dynamic> toJson() => {
        'addon_id': addonId,
        'addon_name': addonName,
        'addon_price': addonPrice,
        if (originalAddonPrice != null) 'original_addon_price': originalAddonPrice,
        'quantity': quantity,
      };

  factory SelectedAddon.fromJson(Map<String, dynamic> json) => SelectedAddon(
        addonId: json['addon_id'] as String,
        addonName: json['addon_name'] as String,
        addonPrice: (json['addon_price'] as num).toDouble(),
        originalAddonPrice: (json['original_addon_price'] as num?)?.toDouble(),
        quantity: (json['quantity'] as int?) ?? 1,
      );
}

/// Builds [SelectedAddon] list from the full catalog and a set of selected IDs.
/// Pass [quantities] to assign per-addon quantities (defaults to 1 otherwise).
List<SelectedAddon> buildSelectedAddons(
  List<AddOnModel> addOns,
  Set<String> selectedIds, {
  Map<String, int> quantities = const {},
}) {
  return addOns
      .where((a) => selectedIds.contains(a.id))
      .map((a) => SelectedAddon(
            addonId: a.id,
            addonName: a.name,
            addonPrice: a.finalPrice,
            originalAddonPrice: a.hasDiscount ? a.price : null,
            quantity: quantities[a.id] ?? 1,
          ))
      .toList();
}

/// Total price contribution from all selected add-ons (quantity-aware).
double totalAddonsPrice(List<SelectedAddon> addOns) =>
    addOns.fold(0.0, (sum, a) => sum + a.addonPrice * a.quantity);
