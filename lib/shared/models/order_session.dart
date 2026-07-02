import 'order.dart';

enum SessionStatus {
  waiting_suppliers,
  all_confirmed,
  out_for_delivery,
  delivered,
  cancelled;

  static SessionStatus from(String s) =>
      SessionStatus.values.firstWhere((e) => e.name == s,
          orElse: () => SessionStatus.waiting_suppliers);

  String get label {
    switch (this) {
      case SessionStatus.waiting_suppliers: return 'Waiting for shops';
      case SessionStatus.all_confirmed: return 'Shops confirmed';
      case SessionStatus.out_for_delivery: return 'Out for delivery';
      case SessionStatus.delivered: return 'Delivered';
      case SessionStatus.cancelled: return 'Cancelled';
    }
  }
}

/// Maps the `order_sessions` table.
class OrderSession {
  final String id;
  final String? displayId;
  final String customerId;
  final String? deliveryId;
  final SessionStatus status;
  final String? deliveryAddress;
  final double? deliveryLat;
  final double? deliveryLng;
  final double deliveryFee;
  final double total;
  final DateTime placedAt;
  final DateTime? deliveredAt;
  final List<Order> subOrders;

  const OrderSession({
    required this.id,
    this.displayId,
    required this.customerId,
    this.deliveryId,
    this.status = SessionStatus.waiting_suppliers,
    this.deliveryAddress,
    this.deliveryLat,
    this.deliveryLng,
    this.deliveryFee = 20,
    this.total = 0,
    required this.placedAt,
    this.deliveredAt,
    this.subOrders = const [],
  });

  factory OrderSession.fromMap(Map<String, dynamic> m,
      {List<Order> subOrders = const []}) =>
      OrderSession(
        id: m['id'] as String,
        displayId: m['display_id'] as String?,
        customerId: m['customer_id'] as String,
        deliveryId: m['delivery_id'] as String?,
        status: SessionStatus.from(m['status'] as String? ?? 'waiting_suppliers'),
        deliveryAddress: m['delivery_address'] as String?,
        deliveryLat: (m['delivery_lat'] as num?)?.toDouble(),
        deliveryLng: (m['delivery_lng'] as num?)?.toDouble(),
        deliveryFee: (m['delivery_fee'] as num?)?.toDouble() ?? 20,
        total: (m['total'] as num?)?.toDouble() ?? 0,
        placedAt: DateTime.tryParse(m['placed_at']?.toString() ?? '') ?? DateTime.now(),
        deliveredAt: m['delivered_at'] != null
            ? DateTime.tryParse(m['delivered_at'].toString())
            : null,
        subOrders: subOrders,
      );

  String get shortId =>
      displayId ?? (id.length >= 8 ? id.substring(0, 8) : id);
}
