import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_session.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';
import 'admin_ui.dart';

/// Sessions table with expandable sub-orders per supplier.
class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});
  @override
  State<AdminOrdersScreen> createState() => _State();
}

class _State extends State<AdminOrdersScreen> {
  List<OrderSession> _sessions = [];
  // sessionId -> sub-orders
  final Map<String, List<Order>> _subOrders = {};
  final Set<String> _expanded = {};
  String _filter = 'all';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await supabase
          .from('order_sessions')
          .select()
          .order('placed_at', ascending: false);
      _sessions =
          (rows as List).map((e) => OrderSession.fromMap(e)).toList();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSubOrders(String sessionId) async {
    if (_subOrders.containsKey(sessionId)) return;
    final rows = await supabase
        .from('orders')
        .select('*, suppliers(shop_name)')
        .eq('session_id', sessionId);
    setState(() {
      _subOrders[sessionId] =
          (rows as List).map((e) => Order.fromMap(e)).toList();
    });
  }

  Future<void> _overrideSession(OrderSession s, String status) async {
    await supabase
        .from('order_sessions')
        .update({'status': status})
        .eq('id', s.id);
    _load();
  }

  List<OrderSession> get _filtered {
    if (_filter == 'all') return _sessions;
    return _sessions.where((s) => s.status.name == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminPageTitle(
            'Orders',
            trailing: Row(
              children: [
                const Text('Filter: ',
                    style: TextStyle(color: AppColors.textMuted)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _filter,
                  items: [
                    'all',
                    ...SessionStatus.values.map((e) => e.name)
                  ]
                      .map((s) =>
                          DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => _filter = v ?? 'all'),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _load,
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(child: Text('No orders found'))
                    : ListView.separated(
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, idx) {
                          final s = _filtered[idx];
                          final isOpen = _expanded.contains(s.id);
                          return AdminCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                // Session header row.
                                InkWell(
                                  onTap: () async {
                                    setState(() {
                                      if (isOpen) {
                                        _expanded.remove(s.id);
                                      } else {
                                        _expanded.add(s.id);
                                      }
                                    });
                                    if (!isOpen) await _loadSubOrders(s.id);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(children: [
                                      Icon(
                                        isOpen
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        color: AppColors.textMuted,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        flex: 2,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text('#${s.shortId}',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w700)),
                                            Text(formatDate(s.placedAt),
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color:
                                                        AppColors.textMuted)),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          s.deliveryAddress ?? '-',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textMuted),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Text(formatRupees(s.total),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600)),
                                      ),
                                      _statusChip(s.status),
                                      const SizedBox(width: 12),
                                      // Status override.
                                      DropdownButton<String>(
                                        value: s.status.name,
                                        underline: const SizedBox.shrink(),
                                        icon: const Icon(Icons.arrow_drop_down,
                                            size: 18),
                                        items: SessionStatus.values
                                            .map((st) => DropdownMenuItem(
                                                value: st.name,
                                                child: Text(st.label,
                                                    style: const TextStyle(
                                                        fontSize: 12))))
                                            .toList(),
                                        onChanged: (v) {
                                          if (v != null &&
                                              v != s.status.name) {
                                            _overrideSession(s, v);
                                          }
                                        },
                                      ),
                                    ]),
                                  ),
                                ),
                                // Expanded: sub-orders per supplier.
                                if (isOpen) ...[
                                  const Divider(height: 1),
                                  if (!_subOrders.containsKey(s.id))
                                    const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: CircularProgressIndicator(),
                                    )
                                  else
                                    ..._subOrders[s.id]!.map(
                                      (o) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 32, vertical: 10),
                                        child: Row(children: [
                                          const Icon(Icons.store,
                                              size: 16,
                                              color: AppColors.primary),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              o.supplierName ??
                                                  o.supplierId
                                                      .substring(0, 8),
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13),
                                            ),
                                          ),
                                          Text(formatRupees(o.subtotal),
                                              style: const TextStyle(
                                                  fontSize: 13)),
                                          const SizedBox(width: 12),
                                          StatusChip.order(o.status),
                                        ]),
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(SessionStatus s) {
    final (label, color) = switch (s) {
      SessionStatus.delivered => ('Delivered', AppColors.secondary),
      SessionStatus.cancelled => ('Cancelled', AppColors.danger),
      SessionStatus.out_for_delivery =>
        ('Out for delivery', AppColors.primary),
      SessionStatus.all_confirmed => ('Confirmed', AppColors.warning),
      SessionStatus.waiting_suppliers => ('Waiting', AppColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
