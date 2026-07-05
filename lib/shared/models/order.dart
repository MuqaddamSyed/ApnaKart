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

/// Maps the `orders` table (one per supplier per session).
class Order {
  final String id;
  final String? sessionId;
  final String? displayId; // friendly order no. (DDMM+seq) from the session
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

  // Joined fields (populated when fetched with relations).
  final String? supplierName;
  final String? supplierPhone;
  final String? supplierAddress;
  final double? supplierLat;
  final double? supplierLng;
  final String? customerPhone;

  Order({
    required this.id,
    this.sessionId,
    this.displayId,
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
    this.supplierName,
    this.supplierPhone,
    this.supplierAddress,
    this.supplierLat,
    this.supplierLng,
    this.customerPhone,
  });

  factory Order.fromMap(Map<String, dynamic> m, {List<OrderItem> items = const []}) {
    final sup = m['suppliers'] as Map<String, dynamic>?;
    final supUser = sup?['users'] as Map<String, dynamic>?;
    final cust = m['customers'] as Map<String, dynamic>?;
    final custUser = cust?['users'] as Map<String, dynamic>?;
    final session = m['order_sessions'] as Map<String, dynamic>?;
    return Order(
      id: m['id'] as String,
      sessionId: m['session_id'] as String?,
      displayId: session?['display_id'] as String?,
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
      deliveredAt: m['delivered_at'] != null
          ? DateTime.tryParse(m['delivered_at'].toString())
          : null,
      items: items,
      supplierName: sup?['shop_name'] as String?,
      supplierPhone: supUser?['phone'] as String?,
      supplierAddress: sup?['address'] as String?,
      supplierLat: (sup?['lat'] as num?)?.toDouble(),
      supplierLng: (sup?['lng'] as num?)?.toDouble(),
      customerPhone: custUser?['phone'] as String?,
    );
  }

  /// Friendly order number for display — the session's DDMM+seq id when
  /// available, else a short slice of the uuid.
  String get orderNo =>
      displayId ?? (id.length >= 8 ? id.substring(0, 8) : id);
}
