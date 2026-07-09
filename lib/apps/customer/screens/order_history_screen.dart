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
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid != null) {
        final all = await ref.read(orderServiceProvider).getOrdersByCustomer(uid);
        // Collapse multi-supplier orders: one card per session (keep standalone
        // legacy orders that have no session_id).
        final seen = <String>{};
        _orders = [
          for (final o in all)
            if (o.sessionId == null || seen.add(o.sessionId!)) o
        ];
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                          title: Text('Order #${o.orderNo}'),
                          subtitle: Text('${formatDate(o.placedAt)}\n${formatRupees(o.total)}'),
                          isThreeLine: true,
                          trailing: StatusBadge(status: o.status),
                          // Only session-based orders can open the tracking
                          // screen (it queries order_sessions by id).
                          onTap: o.sessionId == null
                              ? null
                              : () => context
                                  .push('${Routes.tracking}/${o.sessionId}'),
                        ),
                      )).toList(),
                ),
    );
  }
}
