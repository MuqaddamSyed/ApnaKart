import 'dart:math';
import '../models/order.dart';
import '../models/order_item.dart';
import '../../core/constants/app_constants.dart';
import 'supabase_client.dart';
import 'otp_store.dart';
import 'notification_service.dart';

/// Order placement, status updates, realtime streams, queries.
class OrderService {
  /// Generates a 4-digit delivery OTP (string, zero-padded).
  static String generateOtp() =>
      (Random().nextInt(9000) + 1000).toString();

  /// Places an order with COD. Returns the created order id + plaintext OTP.
  /// The OTP is stored ONLY as a bcrypt hash server-side (via the
  /// `set_order_otp` RPC); the plaintext is kept locally on the customer's
  /// device (Hive/OtpStore) so the tracking screen can display it.
  Future<({String orderId, String otp})> placeOrder({
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
    final otp = generateOtp();

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

    // Hash + store the OTP server-side; keep plaintext only on this device.
    await supabase.rpc('set_order_otp', params: {
      'p_order_id': orderId,
      'p_otp': otp,
    });
    await OtpStore.save(orderId, otp);
    await NotificationService().sendPushToUser(
      supplierId,
      'New order received',
      'A customer placed a new order.',
      type: 'new_order',
    );

    return (orderId: orderId, otp: otp);
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
    final supplierId = row['supplier_id'] as String?;
    final deliveryId = row['delivery_id'] as String?;
    final notifications = NotificationService();

    if (status == OrderStatus.picked_up) {
      await notifications.sendPushToRole(
        'delivery',
        'Order ready for pickup',
        'A supplier marked an order ready for delivery.',
        type: 'delivery_request',
      );
    }
    if (customerId != null) {
      await notifications.sendPushToUser(
        customerId,
        'Order update',
        'Your order is now ${status.label}.',
        type: 'order_update',
      );
    }
    if (status == OrderStatus.cancelled && supplierId != null) {
      await notifications.sendPushToUser(
        supplierId,
        'Order cancelled',
        'A customer cancelled an order.',
        type: 'order_cancelled',
      );
    }
    if (status == OrderStatus.on_the_way && deliveryId != null && customerId != null) {
      await notifications.sendPushToUser(
        customerId,
        'Delivery on the way',
        'Your delivery partner is heading to you.',
        type: 'delivery_assigned',
      );
    }
  }

  Future<void> assignAgent(String orderId, String agentId) async {
    await supabase.from('orders').update({'delivery_id': agentId}).eq('id', orderId);
  }

  /// Verifies the OTP via the `verify-delivery-otp` Edge Function, which
  /// compares against the stored bcrypt hash and, on match, atomically marks
  /// the order delivered and bumps the agent's earnings. Returns true on match.
  Future<bool> confirmDelivery(String orderId, String enteredOtp) async {
    final res = await supabase.functions.invoke(
      'verify-delivery-otp',
      body: {'orderId': orderId, 'otp': enteredOtp},
    );
    final data = res.data;
    if (data is Map && data['success'] == true) return true;
    return false;
  }

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
