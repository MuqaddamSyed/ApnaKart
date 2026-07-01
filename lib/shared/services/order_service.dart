import '../models/order.dart';
import '../models/order_session.dart';
import '../models/order_item.dart';
import '../../core/constants/app_constants.dart';
import 'supabase_client.dart';
import 'notification_service.dart';

/// Order placement, status updates, realtime streams, queries.
class OrderService {
  // ---------------------------------------------------------------
  // PLACEMENT
  // ---------------------------------------------------------------

  /// Places a multi-supplier order. Creates one `order_sessions` row and one
  /// `orders` row per supplier. Returns the session id.
  Future<String> placeMultiSupplierOrder({
    required String customerId,
    required String deliveryAddress,
    double? lat,
    double? lng,
    // supplierId -> list of items for that supplier
    required Map<String, List<OrderItem>> supplierItems,
    String? notes,
  }) async {
    final supplierSubtotals = supplierItems.map(
        (sid, items) => MapEntry(sid, items.fold<double>(0, (s, i) => s + i.totalPrice)));
    final grandSubtotal = supplierSubtotals.values.fold<double>(0, (s, v) => s + v);
    const deliveryFee = AppConstants.flatDeliveryFee;
    final total = grandSubtotal + deliveryFee;

    // Create the session.
    final sessionRow = await supabase.from('order_sessions').insert({
      'customer_id': customerId,
      'status': 'waiting_suppliers',
      'delivery_address': deliveryAddress,
      'delivery_lat': lat,
      'delivery_lng': lng,
      'delivery_fee': deliveryFee,
      'total': total,
    }).select().single();
    final sessionId = sessionRow['id'] as String;

    // Create one order per supplier.
    final notifications = NotificationService();
    for (final entry in supplierItems.entries) {
      final supplierId = entry.key;
      final items = entry.value;
      final subtotal = supplierSubtotals[supplierId]!;

      final orderRow = await supabase.from('orders').insert({
        'session_id': sessionId,
        'customer_id': customerId,
        'supplier_id': supplierId,
        'status': 'placed',
        'payment_method': 'COD',
        'subtotal': subtotal,
        'delivery_fee': 0, // delivery fee is on the session, not per sub-order
        'total': subtotal,
        'delivery_address': deliveryAddress,
        'delivery_lat': lat,
        'delivery_lng': lng,
        'notes': notes,
      }).select().single();
      final orderId = orderRow['id'] as String;

      await supabase.from('order_items').insert(
        items.map((i) => i.toInsert(orderId)).toList(),
      );

      await notifications.sendPushToUser(
        supplierId,
        'New order received',
        'A customer placed a new order. Please confirm.',
        type: 'new_order',
      );
    }

    return sessionId;
  }

  // ---------------------------------------------------------------
  // STATUS UPDATES (sub-orders)
  // ---------------------------------------------------------------

  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    await supabase.from('orders').update({'status': status.name}).eq('id', orderId);
    final row = await supabase
        .from('orders')
        .select('customer_id,supplier_id,delivery_id,session_id')
        .eq('id', orderId)
        .maybeSingle();
    if (row == null) return;

    final customerId = row['customer_id'] as String?;
    final notifications = NotificationService();

    if (status == OrderStatus.confirmed) {
      // If all suppliers in the session confirmed, notify agents.
      final sessionId = row['session_id'] as String?;
      if (sessionId != null) {
        final pending = await supabase
            .from('orders')
            .select('id')
            .eq('session_id', sessionId)
            .not('status', 'in', '("confirmed","cancelled")');
        if ((pending as List).isEmpty) {
          await notifications.sendPushToRole(
            'delivery',
            'New delivery available',
            'All shops accepted — pick it up!',
            type: 'delivery_request',
          );
        }
      }
    }

    if (customerId != null) {
      final (title, body) = switch (status) {
        OrderStatus.cancelled => ('Order rejected', 'Sorry, your order could not be accepted.'),
        OrderStatus.on_the_way => ('On the way', 'Picked up! Your order is on the way.'),
        OrderStatus.arrived => ('Delivery partner arrived', 'Your delivery partner has reached your location. Accept or reject your order.'),
        _ => (null, null),
      };
      if (title != null) {
        await notifications.sendPushToUser(customerId, title, body!, type: 'order_update');
      }
    }
  }

  // ---------------------------------------------------------------
  // SESSION OPERATIONS
  // ---------------------------------------------------------------

  /// Atomically claim an unclaimed session for [agentId]. Returns false if
  /// another agent already claimed it.
  Future<bool> claimSession(String sessionId, String agentId) async {
    final result = await supabase
        .rpc('claim_session', params: {'p_session_id': sessionId, 'p_agent_id': agentId});
    final ok = result as bool? ?? false;
    if (ok) {
      final session = await supabase
          .from('order_sessions')
          .select('customer_id')
          .eq('id', sessionId)
          .maybeSingle();
      final customerId = session?['customer_id'] as String?;
      if (customerId != null) {
        await NotificationService().sendPushToUser(
          customerId,
          'Delivery partner assigned',
          'A delivery partner is on the way.',
          type: 'delivery_assigned',
        );
      }
    }
    return ok;
  }

  Future<void> completeSessionDelivery(String sessionId) async {
    await supabase.rpc('complete_session_delivery', params: {'p_session_id': sessionId});
  }

  Future<void> rejectSessionByCustomer(String sessionId) async {
    await supabase.rpc('reject_session_by_customer', params: {'p_session_id': sessionId});
  }

  /// Mark agent arrived at customer location (updates session sub-orders).
  Future<void> markSessionArrived(String sessionId) async {
    await supabase
        .from('orders')
        .update({'status': OrderStatus.arrived.name})
        .eq('session_id', sessionId)
        .not('status', 'in', '("cancelled","delivered","returned")');
  }

  // ---------------------------------------------------------------
  // PACKING
  // ---------------------------------------------------------------

  Future<void> updateItemAvailability(
      String orderItemId, bool isAvailable, int? availableQty) async {
    await supabase.from('order_item_status').upsert({
      'order_item_id': orderItemId,
      'is_available': isAvailable,
      'available_qty': availableQty,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'order_item_id');
  }

  // ---------------------------------------------------------------
  // LEGACY: single-order claim (kept for backward compat)
  // ---------------------------------------------------------------

  Future<bool> claimOrder(String orderId, String agentId) async {
    final updated = await supabase
        .from('orders')
        .update({'delivery_id': agentId})
        .eq('id', orderId)
        .isFilter('delivery_id', null)
        .select('id');
    return (updated as List).isNotEmpty;
  }

  Future<void> markArrived(String orderId) =>
      updateOrderStatus(orderId, OrderStatus.arrived);

  Future<void> completeDelivery(String orderId) async {
    await supabase.rpc('complete_delivery', params: {'p_order_id': orderId});
  }

  Future<void> rejectByCustomer(String orderId) =>
      updateOrderStatus(orderId, OrderStatus.returned);

  // ---------------------------------------------------------------
  // REALTIME STREAMS
  // ---------------------------------------------------------------

  Stream<Order> listenToOrder(String orderId) {
    return supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .map((rows) => Order.fromMap(rows.first));
  }

  Stream<OrderSession> listenToSession(String sessionId) {
    return supabase
        .from('order_sessions')
        .stream(primaryKey: ['id'])
        .eq('id', sessionId)
        .map((rows) => OrderSession.fromMap(rows.first));
  }

  /// Active and new orders for a supplier (all non-terminal statuses).
  Stream<List<Order>> listenToSupplierOrders(String supplierId) {
    return supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('supplier_id', supplierId)
        .order('placed_at', ascending: false)
        .map((rows) => rows
            .map((e) => Order.fromMap(e))
            .where((o) => ![
                  OrderStatus.delivered,
                  OrderStatus.cancelled,
                  OrderStatus.returned,
                ].contains(o.status))
            .toList());
  }

  /// Sessions ready for pickup (all suppliers confirmed, unassigned).
  Stream<List<OrderSession>> listenToAvailableSessions() {
    return supabase
        .from('order_sessions')
        .stream(primaryKey: ['id'])
        .eq('status', 'all_confirmed')
        .map((rows) => rows
            .map((e) => OrderSession.fromMap(e))
            .where((s) => s.deliveryId == null)
            .toList());
  }

  // ---------------------------------------------------------------
  // QUERIES
  // ---------------------------------------------------------------

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

  Future<List<Order>> getSupplierHistory(String supplierId) async {
    final rows = await supabase
        .from('orders')
        .select()
        .eq('supplier_id', supplierId)
        .eq('status', 'delivered')
        .order('placed_at', ascending: false);
    return (rows as List).map((e) => Order.fromMap(e)).toList();
  }

  Future<double> getTodaySupplierEarnings(String supplierId) async {
    final result = await supabase
        .rpc('get_today_supplier_earnings', params: {'p_supplier_id': supplierId});
    return (result as num?)?.toDouble() ?? 0;
  }

  Future<List<Order>> getSessionOrders(String sessionId) async {
    final rows = await supabase
        .from('orders')
        .select('*, suppliers(shop_name, address, lat, lng, users(phone)), customers(users(phone))')
        .eq('session_id', sessionId);
    return (rows as List).map((e) => Order.fromMap(e)).toList();
  }

  Future<List<OrderItem>> getOrderItems(String orderId) async {
    final rows = await supabase
        .from('order_items')
        .select('''
          *,
          products(name, image_url, unit),
          order_item_status(is_available, available_qty)
        ''')
        .eq('order_id', orderId);
    return (rows as List).map((m) {
      final prod = m['products'] as Map<String, dynamic>?;
      final status = m['order_item_status'] as Map<String, dynamic>?;
      return OrderItem(
        id: m['id'] as String?,
        productId: m['product_id'] as String,
        productName: prod?['name']?.toString() ?? '',
        quantity: m['quantity'] as int,
        unitPrice: (m['unit_price'] as num).toDouble(),
        imageUrl: prod?['image_url'] as String?,
        unit: prod?['unit'] as String?,
        isAvailable: status?['is_available'] as bool?,
        availableQty: status?['available_qty'] as int?,
      );
    }).toList();
  }
}
