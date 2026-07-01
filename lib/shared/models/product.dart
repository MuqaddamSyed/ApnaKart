/// Maps the `products` table.
class Product {
  final String id;
  final String supplierId;
  final String name;
  final String? description;
  final String? imageUrl;
  final String? category;
  final double mrp;
  final double salePrice;
  final int discountPercent;
  final int stockQty;
  final String? unit;
  final bool isAvailable;
  final bool adminManaged;

  Product({
    required this.id,
    required this.supplierId,
    required this.name,
    this.description,
    this.imageUrl,
    this.category,
    required this.mrp,
    required this.salePrice,
    this.discountPercent = 0,
    this.stockQty = 0,
    this.unit,
    this.isAvailable = true,
    this.adminManaged = false,
  });

  factory Product.fromMap(Map<String, dynamic> m) => Product(
        id: m['id'] as String,
        supplierId: m['supplier_id'] as String,
        name: m['name'] as String,
        description: m['description'] as String?,
        imageUrl: m['image_url'] as String?,
        category: m['category'] as String?,
        mrp: (m['mrp'] as num).toDouble(),
        salePrice: (m['sale_price'] as num).toDouble(),
        discountPercent: m['discount_percent'] as int? ?? 0,
        stockQty: m['stock_qty'] as int? ?? 0,
        unit: m['unit'] as String?,
        isAvailable: m['is_available'] as bool? ?? true,
        adminManaged: m['admin_managed'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'supplier_id': supplierId,
        'name': name,
        'description': description,
        'image_url': imageUrl,
        'category': category,
        'mrp': mrp,
        'sale_price': salePrice,
        'stock_qty': stockQty,
        'unit': unit,
        'is_available': isAvailable,
      };
}
