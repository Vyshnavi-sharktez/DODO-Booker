class BookingAddon {
  final String addonId;
  final String name;
  final double price;

  const BookingAddon({
    required this.addonId,
    required this.name,
    required this.price,
  });

  factory BookingAddon.fromMap(Map<String, dynamic> map) {
    return BookingAddon(
      addonId: map['addon_id'] as String? ?? '',
      name: map['addon_name'] as String? ?? '',
      price: (map['addon_price'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
