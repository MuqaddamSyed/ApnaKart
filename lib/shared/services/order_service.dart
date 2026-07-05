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
    // Reject checkout if any shop in the cart has since closed (the DB has a
    // trigger as the airtight backstop; this gives a friendly message first).
    final closedShops = await supabase
        .from('suppliers')
        .select('shop_name, is_open')
        .inFilter('id', supplierItems.keys.toList());
    final closedNames = (closedShops as List)
        .where((s) => s['is_open'] == false)
        .map((s) => (s['shop_name'] as String?) ?? 'A shop')
        .toList();
    if (closedNames.isNotEmpty) {
      throw Exception(
          '${closedNames.join(', ')} is closed right now. Remove those items and try again.');
    }

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

  /// Supplier accepts a single-shop order and delivers it themselves (keeps
  /// the delivery fee). Skips the agent pool entirely.
  Future<void> acceptAndSelfDeliver(String orderId) async {
    await supabase.rpc('accept_and_self_deliver', params: {'p_order_id': orderId});
  }

  /// Sessions a supplier is self-delivering (out for delivery).
  Future<List<OrderSession>> getSupplierSelfDeliveries(String supplierId) async {
    final rows = await supabase
        .from('order_sessions')
        .select()
        .eq('delivery_id', supplierId)
        .eq('delivery_mode', 'self')
        .eq('status', 'out_for_delivery')
        .order('placed_at', ascending: false);
    return (rows as List).map((e) => OrderSession.fromMap(e)).toList();
  }

  /// Delivery-fee earnings the supplier made from self-delivered orders.
  Future<double> getSupplierDeliveryEarnings(String supplierId) async {
    final result = await supabase
        .rpc('get_supplier_delivery_earnings', params: {'p_supplier_id': supplierId});
    return (result as num?)?.toDouble() ?? 0;
  }

  /// Agent completes delivery by entering the handoff code the customer shows.
  Future<void> completeSessionDeliveryWithOtp(String sessionId, String otp) async {
    await supabase.rpc('complete_session_delivery',
        params: {'p_session_id': sessionId, 'p_otp': otp});
  }

  Future<void> rejectSessionByCustomer(String sessionId) async {
    await supabase.rpc('reject_session_by_customer', params: {'p_session_id': sessionId});
  }

  /// Assigned agent rejects/returns the delivery (agent-authorised, unlike
  /// rejectSessionByCustomer which is customer-only).
  Future<void> rejectSessionByAgent(String sessionId) async {
    await supabase.rpc('reject_session_by_agent', params: {'p_session_id': sessionId});
  }

  /// Mark agent arrived: flips sub-orders to 'arrived' and generates the
  /// handoff code (server-side, agent-only).
  Future<void> markSessionArrived(String sessionId) async {
    await supabase.rpc('mark_session_arrived', params: {'p_session_id': sessionId});
  }

  /// The 4-digit handoff code for a session — readable only by the owning
  /// customer (RLS). Returns null until the agent has marked arrival.
  Future<String?> getSessionOtp(String sessionId) async {
    final row = await supabase
        .from('session_handoff')
        .select('otp')
        .eq('session_id', sessionId)
        .maybeSingle();
    return row?['otp'] as String?;
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

  /// Recomputes an order's subtotal from packed (effective) item quantities and
  /// propagates the delta to the parent session total, so the customer is billed
  /// for what was actually available. Runs server-side (SECURITY DEFINER) since
  /// the supplier cannot read sibling sub-orders or the session row under RLS.
  Future<void> recomputeOrderAndSessionTotals(String orderId) async {
    await supabase
        .rpc('recompute_session_total', params: {'p_order_id': orderId});
  }

  /// Customer cancels a whole session before it is picked up.
  Future<void> cancelSessionByCustomer(String sessionId) =>
      rejectSessionByCustomer(sessionId);

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
        .where((rows) => rows.isNotEmpty)
        .map((rows) => Order.fromMap(rows.first));
  }

  Stream<OrderSession> listenToSession(String sessionId) {
    return supabase
        .from('order_sessions')
        .stream(primaryKey: ['id'])
        .eq('id', sessionId)
        .where((rows) => rows.isNotEmpty)
        .map((rows) => OrderSession.fromMap(rows.first));
  }

  /// Live sub-orders (one row per supplier) for a session. Used to derive
  /// arrival/status on the customer and delivery screens in realtime.
  Stream<List<Order>> listenToSessionOrders(String sessionId) {
    return supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .map((rows) => rows.map((e) => Order.fromMap(e)).toList());
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

  /// The assigned delivery agent's contact for an order the caller supplies,
  /// so the supplier can call the partner for pickup. Null if unassigned.
  Future<({String? name, String? phone})> getOrderAgentContact(String orderId) async {
    try {
      final res = await supabase
          .rpc('get_order_agent_contact', params: {'p_order_id': orderId});
      if (res == null) return (name: null, phone: null);
      final m = (res as Map).cast<String, dynamic>();
      return (name: m['name'] as String?, phone: m['phone'] as String?);
    } catch (_) {
      return (name: null, phone: null);
    }
  }

  /// Contacts for a session (server-side, privacy-checked): supplier phones
  /// for any verified agent, customer phone only for the assigned agent.
  /// Returns { supplierPhones: {supplierId: phone}, customerName, customerPhone }.
  Future<({Map<String, String> supplierPhones, String? customerName, String? customerPhone, String? customerAddress})>
      getSessionContacts(String sessionId) async {
    try {
      final res = await supabase
          .rpc('get_session_contacts', params: {'p_session_id': sessionId});
      final map = (res as Map).cast<String, dynamic>();
      final phones = <String, String>{};
      for (final s in (map['suppliers'] as List? ?? [])) {
        final sid = s['supplier_id'] as String?;
        final phone = s['phone'] as String?;
        if (sid != null && phone != null && phone.isNotEmpty) phones[sid] = phone;
      }
      final cust = map['customer'] as Map?;
      return (
        supplierPhones: phones,
        customerName: cust?['name'] as String?,
        customerPhone: cust?['phone'] as String?,
        customerAddress: cust?['address'] as String?,
      );
    } catch (_) {
      return (
        supplierPhones: <String, String>{},
        customerName: null,
        customerPhone: null,
        customerAddress: null
      );
    }
  }

  /// Total COD cash a delivery agent has collected across all delivered
  /// orders (caller-checked server-side).
  Future<double> getAgentCodTotal(String agentId) async {
    final result = await supabase
        .rpc('get_agent_cod_total', params: {'p_agent_id': agentId});
    return (result as num?)?.toDouble() ?? 0;
  }

  /// Sessions ready for pickup — direct fetch (RLS-filtered). Used so the
  /// delivery pool doesn't depend solely on realtime, which can silently fail
  /// to deliver the row and leave the agent with an empty screen.
  Future<List<OrderSession>> getAvailableSessions() async {
    final rows = await supabase
        .from('order_sessions')
        .select()
        .eq('status', 'all_confirmed')
        .isFilter('delivery_id', null)
        .order('placed_at', ascending: false);
    return (rows as List).map((e) => OrderSession.fromMap(e)).toList();
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

  /// Lifetime earnings: sum of subtotals across all delivered orders.
  Future<double> getTotalSupplierEarnings(String supplierId) async {
    final result = await supabase
        .rpc('get_total_supplier_earnings', params: {'p_supplier_id': supplierId});
    return (result as num?)?.toDouble() ?? 0;
  }

  Future<List<Order>> getSessionOrders(String sessionId) async {
    final rows = await supabase
        .from('orders')
        .select('*, suppliers(shop_name, address, lat, lng, users(phone)), customers(users(phone))')
        .eq('session_id', sessionId);
    return (rows as List).map((e) => Order.fromMap(e)).toList();
  }

  /// Number of supplier sub-orders (shops) in a session. Used by the delivery
  /// list/sheet where the session stream itself doesn't carry sub-orders.
  Future<int> getSessionShopCount(String sessionId) async {
    final rows = await supabase
        .from('orders')
        .select('id')
        .eq('session_id', sessionId);
    return (rows as List).length;
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
        quantity: (m['quantity'] as num?)?.toInt() ?? 0,
        unitPrice: (m['unit_price'] as num?)?.toDouble() ?? 0,
        imageUrl: prod?['image_url'] as String?,
        unit: prod?['unit'] as String?,
        isAvailable: status?['is_available'] as bool?,
        availableQty: status?['available_qty'] as int?,
      );
    }).toList();
  }
}
