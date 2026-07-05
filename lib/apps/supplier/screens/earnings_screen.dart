import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/order.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';

/// Earnings with Today/Week/Month toggle + completed order list.
class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});
  @override
  ConsumerState<EarningsScreen> createState() => _State();
}

class _State extends ConsumerState<EarningsScreen> {
  int _range = 0; // 0 today, 1 week, 2 month
  List<Order> _orders = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid != null) {
      _orders = (await ref.read(orderServiceProvider).getOrdersBySupplier(uid))
          .where((o) => o.status == OrderStatus.delivered).toList();
    }
    setState(() => _loading = false);
  }

  List<Order> get _filtered {
    final now = DateTime.now();
    return _orders.where((o) {
      // placed_at is UTC; compare in local time so "today" is the real day.
      final placed = o.placedAt.toLocal();
      final diff = now.difference(placed).inDays;
      if (_range == 0) {
        return placed.year == now.year &&
            placed.month == now.month &&
            placed.day == now.day;
      }
      if (_range == 1) return diff < 7;
      return diff < 30;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final f = _filtered;
    final revenue = f.fold<double>(0, (s, o) => s + o.total);
    final aov = f.isEmpty ? 0 : revenue / f.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Today')),
                      ButtonSegment(value: 1, label: Text('Week')),
                      ButtonSegment(value: 2, label: Text('Month')),
                    ],
                    selected: {_range},
                    onSelectionChanged: (s) => setState(() => _range = s.first),
                  ),
                ),
                Row(children: [
                  _stat('Orders', '${f.length}'),
                  _stat('Revenue', formatRupees(revenue)),
                  _stat('Avg Order', formatRupees(aov)),
                ]),
                const Divider(),
                Expanded(
                  child: ListView(
                    children: f.map((o) => ListTile(
                          title: Text('#${o.orderNo}'),
                          subtitle: Text(formatDate(o.placedAt)),
                          trailing: Text(formatRupees(o.total),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        )).toList(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _stat(String l, String v) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary)),
            Text(l, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
        ),
      );
}
