import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/order.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';
import 'packing_screen.dart';

/// Three tabs: New (realtime), Active, Completed (history).
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
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
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
      }
    }
    if (mounted) setState(() => _loading = false);
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
          labelColor: AppColors.primary,
          indicatorColor: AppColors.primary,
          tabs: const [Tab(text: 'New'), Tab(text: 'Active'), Tab(text: 'Completed')],
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
              _historyList(),
            ],
          );
        },
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
            actions,
          ],
        ),
      ),
    );
  }

  Widget _newActions(Order o) => Row(children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () => ref
                .read(orderServiceProvider)
                .updateOrderStatus(o.id, OrderStatus.confirmed),
            child: const Text('Accept'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            style:
                OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => ref
                .read(orderServiceProvider)
                .updateOrderStatus(o.id, OrderStatus.cancelled),
            child: const Text('Reject'),
          ),
        ),
      ]);

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
