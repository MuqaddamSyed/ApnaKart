/// Maps the `order_items` table (and doubles as a cart line).
class OrderItem {
  final String? id;
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  String? imageUrl;
  String? unit;

  OrderItem({
    this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.imageUrl,
    this.unit,
  });

  double get totalPrice => unitPrice * quantity;

  factory OrderItem.fromMap(Map<String, dynamic> m) => OrderItem(
        id: m['id'] as String?,
        productId: m['product_id'] as String,
        productName: m['product_name']?.toString() ?? '',
        quantity: m['quantity'] as int,
        unitPrice: (m['unit_price'] as num).toDouble(),
      );

  Map<String, dynamic> toInsert(String orderId) => {
        'order_id': orderId,
        'product_id': productId,
        'quantity': quantity,
        'unit_price': unitPrice,
        'total_price': totalPrice,
      };

  OrderItem copyWith({int? quantity}) => OrderItem(
        id: id,
        productId: productId,
        productName: productName,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice,
        imageUrl: imageUrl,
        unit: unit,
      );
}
