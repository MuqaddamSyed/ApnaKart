import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/models/order.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/skeleton.dart';

/// Past orders list -> tap to track/detail.
class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});
  @override
  ConsumerState<OrderHistoryScreen> createState() => _State();
}

class _State extends ConsumerState<OrderHistoryScreen> {
  List<Order> _orders = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid != null) {
      _orders = await ref.read(orderServiceProvider).getOrdersByCustomer(uid);
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Orders')),
      body: _loading
          ? const SkeletonList()
          : _orders.isEmpty
              ? const Center(child: Text('No orders yet'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: _orders.map((o) => Card(
                        child: ListTile(
                          title: Text('Order #${(o.sessionId ?? o.id).substring(0, 8)}'),
                          subtitle: Text('${formatDate(o.placedAt)}\n${formatRupees(o.total)}'),
                          isThreeLine: true,
                          trailing: StatusBadge(status: o.status),
                          onTap: () => context.push('${Routes.tracking}/${o.sessionId ?? o.id}'),
                        ),
                      )).toList(),
                ),
    );
  }
}
