import '../models/order.dart';
import '../models/order_item.dart';
import '../../core/constants/app_constants.dart';
import 'supabase_client.dart';
import 'notification_service.dart';

/// Order placement, status updates, realtime streams, queries.
class OrderService {
  /// Places a COD order and returns its id. Delivery is confirmed by the agent
  /// in-app (no OTP). The supplier is notified of the new order.
  Future<String> placeOrder({
    required String customerId,
    required String supplierId,
    required List<OrderItem> items,
    required String address,
    double? lat,
    double? lng,
    String? notes,
  }) async {
    final subtotal = items.fold<double>(0, (s, i) => s + i.totalPrice);
    const deliveryFee = AppConstants.flatDeliveryFee;
    final total = subtotal + deliveryFee;

    final order = await supabase.from('orders').insert({
      'customer_id': customerId,
      'supplier_id': supplierId,
      'status': 'placed',
      'payment_method': 'COD',
      'subtotal': subtotal,
      'delivery_fee': deliveryFee,
      'total': total,
      'delivery_address': address,
      'delivery_lat': lat,
      'delivery_lng': lng,
      'notes': notes,
    }).select().single();

    final orderId = order['id'] as String;
    await supabase.from('order_items').insert(
      items.map((i) => i.toInsert(orderId)).toList(),
    );

    // Notify the supplier of the new order (best-effort push).
    await NotificationService().sendPushToUser(
      supplierId,
      'New order received',
      'A customer placed a new order for your shop.',
      type: 'new_order',
    );

    return orderId;
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    await supabase.from('orders').update({'status': status.name}).eq('id', orderId);
    final row = await supabase
        .from('orders')
        .select('customer_id,supplier_id,delivery_id')
        .eq('id', orderId)
        .maybeSingle();
    if (row == null) return;

    final customerId = row['customer_id'] as String?;
    final notifications = NotificationService();

    // Supplier accepted → release to the delivery pool + tell online agents.
    if (status == OrderStatus.confirmed) {
      await notifications.sendPushToRole(
        'delivery',
        'New delivery available',
        'A shop accepted an order — accept it to deliver.',
        type: 'delivery_request',
      );
    }
    // Customer is notified ONLY for: rejected, on-the-way, and arrived.
    if (customerId != null) {
      final (title, body) = switch (status) {
        OrderStatus.cancelled => ('Order rejected', 'Sorry, your order could not be accepted.'),
        OrderStatus.on_the_way => ('On the way', 'Picked up! Your order is on the way.'),
        OrderStatus.arrived => ('Delivery partner arrived', 'Your delivery partner has reached your location.'),
        _ => (null, null),
      };
      if (title != null) {
        await notifications.sendPushToUser(customerId, title, body!, type: 'order_update');
      }
    }
  }

  /// Atomically claim an unassigned order for [agentId]. Returns false if
  /// another agent already took it (delivery_id was not null).
  Future<bool> claimOrder(String orderId, String agentId) async {
    final updated = await supabase
        .from('orders')
        .update({'delivery_id': agentId})
        .eq('id', orderId)
        .isFilter('delivery_id', null)
        .select('id');
    final ok = (updated as List).isNotEmpty;
    if (ok) {
      final row = await supabase
          .from('orders')
          .select('customer_id')
          .eq('id', orderId)
          .maybeSingle();
      final customerId = row?['customer_id'] as String?;
      if (customerId != null) {
        await NotificationService().sendPushToUser(
          customerId,
          'Delivery partner assigned',
          'A delivery partner is picking up your order.',
          type: 'delivery_assigned',
        );
      }
    }
    return ok;
  }

  /// Agent reached the customer's location.
  Future<void> markArrived(String orderId) =>
      updateOrderStatus(orderId, OrderStatus.arrived);

  /// Customer accepted the order → mark delivered + credit the agent
  /// (server-side, atomic, no OTP). Supplier's earnings reflect it via the
  /// delivered status. Throws on failure.
  Future<void> completeDelivery(String orderId) async {
    await supabase.rpc('complete_delivery', params: {'p_order_id': orderId});
  }

  /// Customer refused the order at the door.
  Future<void> rejectByCustomer(String orderId) =>
      updateOrderStatus(orderId, OrderStatus.returned);

  /// Realtime stream for a single order (status + agent changes).
  Stream<Order> listenToOrder(String orderId) {
    return supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .map((rows) => Order.fromMap(rows.first));
  }

  /// Realtime stream of new/active orders for a supplier.
  Stream<List<Order>> listenToSupplierOrders(String supplierId) {
    return supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('supplier_id', supplierId)
        .order('placed_at')
        .map((rows) => rows.map((e) => Order.fromMap(e)).toList());
  }

  Future<List<Order>> getOrdersByCustomer(String customerId) async {
    final rows = await supabase
        .from('orders')
        .select()
        .eq('customer_id', customerId)
        .order('placed_at', ascending: false);
    return (rows as List).map((e) => Order.fromMap(e)).toList();
  }

  Future<List<Order>> getOrdersBySupplier(String supplierId) async {
    final rows = await supabase
        .from('orders')
        .select()
        .eq('supplier_id', supplierId)
        .order('placed_at', ascending: false);
    return (rows as List).map((e) => Order.fromMap(e)).toList();
  }

  Future<List<OrderItem>> getOrderItems(String orderId) async {
    final rows = await supabase
        .from('order_items')
        .select('*, products(name, image_url, unit)')
        .eq('order_id', orderId);
    return (rows as List).map((m) {
      final prod = m['products'] as Map<String, dynamic>?;
      return OrderItem(
        id: m['id'] as String?,
        productId: m['product_id'] as String,
        productName: prod?['name']?.toString() ?? '',
        quantity: m['quantity'] as int,
        unitPrice: (m['unit_price'] as num).toDouble(),
        imageUrl: prod?['image_url'] as String?,
        unit: prod?['unit'] as String?,
      );
    }).toList();
  }
}
