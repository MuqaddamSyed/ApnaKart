import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/order.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';

/// Three tabs: New (realtime), Active, Completed (today).
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});
  @override
  ConsumerState<OrdersScreen> createState() => _State();
}

class _State extends ConsumerState<OrdersScreen> {
  bool _approved = false;
  bool _hasShopProfile = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadApproval();
  }

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
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Orders'),
          bottom: const TabBar(
            labelColor: AppColors.primary,
            indicatorColor: AppColors.primary,
            tabs: [Tab(text: 'New'), Tab(text: 'Active'), Tab(text: 'Completed')],
          ),
        ),
        body: StreamBuilder<List<Order>>(
          stream: ref.read(orderServiceProvider).listenToSupplierOrders(uid),
          builder: (context, snap) {
            final orders = snap.data ?? [];
            final isToday = (Order o) => o.placedAt.day == DateTime.now().day;
            final newOrders = orders.where((o) => o.status == OrderStatus.placed).toList();
            final active = orders.where((o) => [
                  OrderStatus.confirmed, OrderStatus.preparing,
                  OrderStatus.picked_up, OrderStatus.on_the_way
                ].contains(o.status)).toList();
            final done = orders.where((o) => o.status == OrderStatus.delivered && isToday(o)).toList();
            return TabBarView(children: [
              _list(newOrders, _newActions),
              _list(active, _activeActions),
              _list(done, (_) => const SizedBox.shrink()),
            ]);
          },
        ),
      ),
    );
  }

  Widget _list(List<Order> orders, Widget Function(Order) actions) {
    if (orders.isEmpty) return const Center(child: Text('No orders'));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: orders.map((o) => Card(
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
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ),
                  Text(formatDate(o.placedAt),
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 8),
                  actions(o),
                ],
              ),
            ),
          )).toList(),
    );
  }

  Widget _newActions(Order o) => Row(children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () => ref.read(orderServiceProvider)
                .updateOrderStatus(o.id, OrderStatus.confirmed),
            child: const Text('Accept'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => ref.read(orderServiceProvider)
                .updateOrderStatus(o.id, OrderStatus.cancelled),
            child: const Text('Reject'),
          ),
        ),
      ]);

  Widget _activeActions(Order o) {
    if (o.status == OrderStatus.confirmed) {
      return ElevatedButton(
        onPressed: () => ref.read(orderServiceProvider)
            .updateOrderStatus(o.id, OrderStatus.preparing),
        child: const Text('Start Preparing'),
      );
    }
    if (o.status == OrderStatus.preparing) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
        onPressed: () => ref.read(orderServiceProvider)
            .updateOrderStatus(o.id, OrderStatus.picked_up),
        child: const Text('Mark Ready for Pickup'),
      );
    }
    return Text('Status: ${o.status.label}',
        style: const TextStyle(color: AppColors.textMuted));
  }
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
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
