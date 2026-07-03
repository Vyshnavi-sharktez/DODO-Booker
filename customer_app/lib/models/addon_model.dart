class AddOnModel {
  final String id;
  final String name;
  final String? description;
  final double price;

  const AddOnModel({
    required this.id,
    required this.name,
    this.description,
    required this.price,
  });

  factory AddOnModel.fromJson(Map<String, dynamic> json) {
    return AddOnModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      price: (json['price'] as num).toDouble(),
    );
  }
}

/// An add-on the customer has chosen for a booking, with the price locked at
/// selection time so it survives admin edits.
class SelectedAddon {
  final String addonId;
  final String addonName;
  final double addonPrice;

  const SelectedAddon({
    required this.addonId,
    required this.addonName,
    required this.addonPrice,
  });

  Map<String, dynamic> toJson() => {
        'addon_id': addonId,
        'addon_name': addonName,
        'addon_price': addonPrice,
      };
}

/// Builds [SelectedAddon] list from the full catalog and a set of selected IDs.
List<SelectedAddon> buildSelectedAddons(
  List<AddOnModel> addOns,
  Set<String> selectedIds,
) {
  return addOns
      .where((a) => selectedIds.contains(a.id))
      .map((a) => SelectedAddon(
            addonId: a.id,
            addonName: a.name,
            addonPrice: a.price,
          ))
      .toList();
}

/// Total price contribution from all selected add-ons.
double totalAddonsPrice(List<SelectedAddon> addOns) =>
    addOns.fold(0.0, (sum, a) => sum + a.addonPrice);
