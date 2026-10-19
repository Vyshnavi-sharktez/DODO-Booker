class BookingAddon {
  final String addonId;
  final String name;
  final double price;
  final int quantity;
  final bool isGlobal;

  const BookingAddon({
    required this.addonId,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.isGlobal = false,
  });

  factory BookingAddon.fromMap(Map<String, dynamic> map) {
    return BookingAddon(
      addonId: map['addon_id'] as String? ?? '',
      name: map['addon_name'] as String? ?? '',
      price: (map['addon_price'] as num?)?.toDouble() ?? 0.0,
      quantity: (map['quantity'] as int?) ?? 1,
      isGlobal: (map['is_global'] as bool?) ?? false,
    );
  }
}
