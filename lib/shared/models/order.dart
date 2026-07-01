import 'order_item.dart';

/// Order status lifecycle.
enum OrderStatus {
  placed, confirmed, preparing, picked_up, on_the_way, arrived, delivered, returned, cancelled;

  static OrderStatus from(String s) =>
      OrderStatus.values.firstWhere((e) => e.name == s, orElse: () => OrderStatus.placed);

  String get label {
    switch (this) {
      case OrderStatus.placed: return 'Placed';
      case OrderStatus.confirmed: return 'Confirmed';
      case OrderStatus.preparing: return 'Preparing';
      case OrderStatus.picked_up: return 'Picked Up';
      case OrderStatus.on_the_way: return 'On The Way';
      case OrderStatus.arrived: return 'Reached You';
      case OrderStatus.delivered: return 'Delivered';
      case OrderStatus.returned: return 'Returned';
      case OrderStatus.cancelled: return 'Cancelled';
    }
  }
}

/// Maps the `orders` table.
class Order {
  final String id;
  final String customerId;
  final String supplierId;
  final String? deliveryId;
  final OrderStatus status;
  final String paymentMethod;
  final String paymentStatus;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final String? deliveryAddress;
  final double? deliveryLat;
  final double? deliveryLng;
  final String? notes;
  final DateTime placedAt;
  final DateTime? deliveredAt;
  final List<OrderItem> items;

  Order({
    required this.id,
    required this.customerId,
    required this.supplierId,
    this.deliveryId,
    this.status = OrderStatus.placed,
    this.paymentMethod = 'COD',
    this.paymentStatus = 'pending',
    this.subtotal = 0,
    this.deliveryFee = 20,
    this.total = 0,
    this.deliveryAddress,
    this.deliveryLat,
    this.deliveryLng,
    this.notes,
    required this.placedAt,
    this.deliveredAt,
    this.items = const [],
  });

  factory Order.fromMap(Map<String, dynamic> m, {List<OrderItem> items = const []}) => Order(
        id: m['id'] as String,
        customerId: m['customer_id'] as String,
        supplierId: m['supplier_id'] as String,
        deliveryId: m['delivery_id'] as String?,
        status: OrderStatus.from(m['status'] as String? ?? 'placed'),
        paymentMethod: m['payment_method'] as String? ?? 'COD',
        paymentStatus: m['payment_status'] as String? ?? 'pending',
        subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0,
        deliveryFee: (m['delivery_fee'] as num?)?.toDouble() ?? 20,
        total: (m['total'] as num?)?.toDouble() ?? 0,
        deliveryAddress: m['delivery_address'] as String?,
        deliveryLat: (m['delivery_lat'] as num?)?.toDouble(),
        deliveryLng: (m['delivery_lng'] as num?)?.toDouble(),
        notes: m['notes'] as String?,
        placedAt: DateTime.tryParse(m['placed_at']?.toString() ?? '') ?? DateTime.now(),
        deliveredAt: m['delivered_at'] != null ? DateTime.tryParse(m['delivered_at'].toString()) : null,
        items: items,
      );
}
