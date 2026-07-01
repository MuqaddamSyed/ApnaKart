import 'package:flutter/material.dart';
import '../../../shared/models/order.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';

/// Full orders table with status filter + manual status override.
class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});
  @override
  State<AdminOrdersScreen> createState() => _State();
}

class _State extends State<AdminOrdersScreen> {
  List<Order> _orders = [];
  String _filter = 'all';
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final rows = await supabase.from('orders').select().order('placed_at', ascending: false);
    _orders = (rows as List).map((e) => Order.fromMap(e)).toList();
    setState(() => _loading = false);
  }

  Future<void> _override(Order o, OrderStatus s) async {
    await supabase.from('orders').update({'status': s.name}).eq('id', o.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final filtered = _filter == 'all'
        ? _orders
        : _orders.where((o) => o.status.name == _filter).toList();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Orders', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const Spacer(),
          DropdownButton<String>(
            value: _filter,
            items: ['all', ...OrderStatus.values.map((e) => e.name)]
                .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) => setState(() => _filter = v ?? 'all'),
          ),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Order')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Total')),
                DataColumn(label: Text('Placed')),
                DataColumn(label: Text('Override')),
              ],
              rows: filtered.map((o) => DataRow(cells: [
                    DataCell(Text('#${o.id.substring(0, 8)}')),
                    DataCell(Text(o.status.label)),
                    DataCell(Text(formatRupees(o.total))),
                    DataCell(Text(formatDate(o.placedAt))),
                    DataCell(DropdownButton<OrderStatus>(
                      value: o.status,
                      underline: const SizedBox.shrink(),
                      items: OrderStatus.values
                          .map((s) => DropdownMenuItem(value: s, child: Text(s.label))).toList(),
                      onChanged: (s) { if (s != null) _override(o, s); },
                    )),
                  ])).toList(),
            ),
          ),
        ),
      ]),
    );
  }
}
