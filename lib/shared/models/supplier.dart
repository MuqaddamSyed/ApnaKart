/// Maps the `suppliers` table.
class Supplier {
  final String id;
  final String shopName;
  final String? address;
  final double? lat;
  final double? lng;
  final List<String> category;
  final bool isVerified;
  final bool isOpen;
  final double rating;

  Supplier({
    required this.id,
    required this.shopName,
    this.address,
    this.lat,
    this.lng,
    this.category = const [],
    this.isVerified = false,
    this.isOpen = true,
    this.rating = 0.0,
  });

  factory Supplier.fromMap(Map<String, dynamic> m) => Supplier(
        id: m['id'] as String,
        shopName: m['shop_name'] as String,
        address: m['address'] as String?,
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        category: (m['category'] as List?)?.map((e) => e.toString()).toList() ?? [],
        isVerified: m['is_verified'] as bool? ?? false,
        isOpen: m['is_open'] as bool? ?? true,
        rating: (m['rating'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'shop_name': shopName,
        'address': address,
        'lat': lat,
        'lng': lng,
        'category': category,
        'is_verified': isVerified,
        'is_open': isOpen,
        'rating': rating,
      };
}
