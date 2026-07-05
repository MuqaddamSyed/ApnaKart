import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_item.dart';
import '../../../shared/models/order_session.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';
import 'packing_screen.dart';
import 'self_delivery_screen.dart';

/// Four tabs: New (realtime), Active, My Deliveries (self-delivered), Completed.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});
  @override
  ConsumerState<OrdersScreen> createState() => _State();
}

class _State extends ConsumerState<OrdersScreen> with SingleTickerProviderStateMixin {
  bool _approved = false;
  bool _hasShopProfile = false;
  bool _loading = true;
  List<Order> _history = [];
  List<OrderSession> _selfDeliveries = [];
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _loadApproval();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _loadApproval() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid != null) {
      final shop = await supabase
          .from('suppliers')
          .select('is_verified')
          .eq('id', uid)
          .maybeSingle();
      _hasShopProfile = shop != null;
      _approved = shop?['is_verified'] as bool? ?? false;
      if (_approved) {
        _history = await ref.read(orderServiceProvider).getSupplierHistory(uid);
        await _loadSelfDeliveries();
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSelfDeliveries() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    final list =
        await ref.read(orderServiceProvider).getSupplierSelfDeliveries(uid);
    if (mounted) setState(() => _selfDeliveries = list);
  }

  Future<void> _selfDeliver(Order o) async {
    try {
      await ref.read(orderServiceProvider).acceptAndSelfDeliver(o.id);
      if (!mounted) return;
      await _loadSelfDeliveries();
      _tab.animateTo(2); // jump to My Deliveries
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('You are delivering this order — see "My Deliveries".')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return const SizedBox.shrink();
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_hasShopProfile) {
      return const _ApprovalMessage(
        title: 'Shop profile pending',
        message: 'Ask the admin to create your supplier profile before receiving orders.',
      );
    }
    if (!_approved) {
      return const _ApprovalMessage(
        title: 'Waiting for admin approval',
        message: 'New orders will be available after your shop is verified.',
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: AppColors.primary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'New'),
            Tab(text: 'Active'),
            Tab(text: 'My Deliveries'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: StreamBuilder<List<Order>>(
        stream: ref.read(orderServiceProvider).listenToSupplierOrders(uid),
        builder: (context, snap) {
          final orders = snap.data ?? [];
          final newOrders = orders.where((o) => o.status == OrderStatus.placed).toList();
          final active = orders.where((o) => [
            OrderStatus.confirmed,
            OrderStatus.preparing,
            OrderStatus.picked_up,
            OrderStatus.on_the_way,
            OrderStatus.arrived,
          ].contains(o.status)).toList();

          return TabBarView(
            controller: _tab,
            children: [
              _list(newOrders, _newActions),
              _list(active, _activeActions),
              _myDeliveriesList(),
              _historyList(),
            ],
          );
        },
      ),
    );
  }

  Widget _myDeliveriesList() {
    if (_selfDeliveries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadSelfDeliveries,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No orders you are delivering yourself')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadSelfDeliveries,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: _selfDeliveries
            .map((s) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.directions_bike,
                        color: AppColors.secondary),
                    title: Text('Order #${s.shortId}'),
                    subtitle: Text(s.deliveryAddress ?? ''),
                    trailing: ElevatedButton(
                      child: const Text('Deliver'),
                      onPressed: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              SelfDeliveryScreen(sessionId: s.id),
                        ));
                        _loadSelfDeliveries();
                      },
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _list(List<Order> orders, Widget Function(Order) actions) {
    if (orders.isEmpty) return const Center(child: Text('No orders'));
    return RefreshIndicator(
      onRefresh: _loadApproval,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: orders.map((o) => _orderCard(o, actions(o))).toList(),
      ),
    );
  }

  Widget _historyList() {
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, color: AppColors.textMuted, size: 48),
            const SizedBox(height: 12),
            const Text('No completed orders yet'),
            TextButton(onPressed: _loadApproval, child: const Text('Refresh')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadApproval,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: _history.map((o) => _orderCard(o, _completedBadge())).toList(),
      ),
    );
  }

  Widget _orderCard(Order o, Widget actions) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('#${o.id.substring(0, 8)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(formatRupees(o.total),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            if (o.notes != null && o.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Note: ${o.notes}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
              ),
            Text(formatDate(o.placedAt),
                style:
                    const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 8),
            // Ordered products so the supplier knows what to pack/confirm.
            _itemsList(o.id),
            // Delivery partner's contact once the order has been claimed.
            _agentContact(o),
            const SizedBox(height: 8),
            actions,
          ],
        ),
      ),
    );
  }

  /// Fetches and lists the products in an order (name × qty · line total),
  /// so the supplier can see exactly what was ordered before accepting.
  Widget _itemsList(String orderId) {
    return FutureBuilder<List<OrderItem>>(
      future: ref.read(orderServiceProvider).getOrderItems(orderId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Loading items…',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          );
        }
        final items = snap.data!;
        if (items.isEmpty) {
          return const Text('No item details',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted));
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Items',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted)),
              const SizedBox(height: 4),
              ...items.map((it) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          '${it.productName}'
                          '${it.unit != null && it.unit!.isNotEmpty ? ' (${it.unit})' : ''}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text('× ${it.quantity}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      Text(formatRupees(it.unitPrice * it.quantity),
                          style: const TextStyle(fontSize: 13)),
                    ]),
                  )),
            ],
          ),
        );
      },
    );
  }

  Future<void> _call(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  /// Shows the assigned delivery partner's name + phone (with a call button)
  /// once an agent has claimed the order. Renders nothing before that.
  Widget _agentContact(Order o) {
    // No agent until the order has been accepted and moved past 'placed'.
    if (o.status == OrderStatus.placed || o.status == OrderStatus.cancelled) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<({String? name, String? phone})>(
      future: ref.read(orderServiceProvider).getOrderAgentContact(o.id),
      builder: (context, snap) {
        final phone = snap.data?.phone;
        if (phone == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.secondary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.delivery_dining,
                  color: AppColors.secondary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(snap.data?.name ?? 'Delivery partner',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(phone,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.secondary)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.call, color: AppColors.secondary),
                tooltip: 'Call delivery partner',
                onPressed: () => _call(phone),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _newActions(Order o) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Self-delivery only for single-shop orders (a shopkeeper can't
        // deliver another shop's items). Green = deliver myself.
        if (o.sessionId != null)
          FutureBuilder<int>(
            future: ref
                .read(orderServiceProvider)
                .getSessionShopCount(o.sessionId!),
            builder: (context, snap) {
              if (snap.data != 1) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white),
                  icon: const Icon(Icons.directions_bike, size: 18),
                  label: const Text('Accept & deliver myself (+delivery fee)'),
                  onPressed: () => _selfDeliver(o),
                ),
              );
            },
          ),
        // Blue = accept and let a delivery partner take it.
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white),
          icon: const Icon(Icons.person_pin_circle, size: 18),
          label: const Text('Accept (assign a partner)'),
          onPressed: () => ref
              .read(orderServiceProvider)
              .updateOrderStatus(o.id, OrderStatus.confirmed),
        ),
        const SizedBox(height: 8),
        // Red = reject.
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          icon: const Icon(Icons.cancel, size: 18),
          label: const Text('Reject order'),
          onPressed: () => ref
              .read(orderServiceProvider)
              .updateOrderStatus(o.id, OrderStatus.cancelled),
        ),
      ],
    );
  }

  Widget _activeActions(Order o) {
    if (o.status == OrderStatus.confirmed) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.hourglass_top, size: 16, color: AppColors.warning),
          const SizedBox(width: 6),
          const Expanded(
              child: Text('Accepted — start packing',
                  style: TextStyle(color: AppColors.warning))),
        ]),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.inventory_2, size: 16),
          label: const Text('Open Packing Screen'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PackingScreen(orderId: o.id),
            ),
          ),
        ),
      ]);
    }
    final (icon, text, color) = switch (o.status) {
      OrderStatus.preparing => (Icons.inventory_2, 'Packing in progress', AppColors.warning),
      OrderStatus.picked_up => (Icons.local_shipping, 'Picked up by delivery partner', AppColors.primary),
      OrderStatus.on_the_way => (Icons.local_shipping, 'On the way to customer', AppColors.primary),
      OrderStatus.arrived => (Icons.location_on, 'Delivery partner reached customer', AppColors.secondary),
      _ => (Icons.info_outline, o.status.label, AppColors.textMuted),
    };
    return Row(children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Expanded(
          child: Text(text,
              style: TextStyle(color: color, fontWeight: FontWeight.w500))),
    ]);
  }

  Widget _completedBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.secondary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Completed',
          style: TextStyle(
              color: AppColors.secondary,
              fontWeight: FontWeight.w600,
              fontSize: 12),
        ),
      );
}

class _ApprovalMessage extends StatelessWidget {
  final String title;
  final String message;
  const _ApprovalMessage({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_top, color: AppColors.warning, size: 44),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
