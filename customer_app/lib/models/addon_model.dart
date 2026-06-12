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
