import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/order.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';
import 'admin_ui.dart';

/// KPI cards + 7-day orders line chart + live recent orders.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});
  @override
  State<OverviewScreen> createState() => _State();
}

class _State extends State<OverviewScreen> {
  List<Order> _orders = [];
  int _suppliers = 0, _customers = 0, _activeDeliveries = 0;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final orders = await supabase.from('orders').select().order('placed_at', ascending: false);
    _orders = (orders as List).map((e) => Order.fromMap(e)).toList();
    _suppliers = (await supabase.from('suppliers').select('id')).length;
    _customers = (await supabase.from('customers').select('id')).length;
    _activeDeliveries = _orders.where((o) => [
          OrderStatus.picked_up, OrderStatus.on_the_way
        ].contains(o.status)).length;
    setState(() => _loading = false);
  }

  List<double> _last7Days() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      return _orders.where((o) =>
          o.placedAt.year == day.year &&
          o.placedAt.month == day.month &&
          o.placedAt.day == day.day).length.toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final today = _orders.where((o) => o.placedAt.day == DateTime.now().day);
    final revenue = today.fold<double>(0, (s, o) => s + o.total);
    final series = _last7Days();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const AdminPageTitle('Dashboard overview'),
        Wrap(spacing: 16, runSpacing: 16, children: [
          KpiCard(label: 'Orders Today', value: '${today.length}', icon: Icons.shopping_bag, color: AppColors.primary),
          KpiCard(label: 'Revenue Today', value: formatRupees(revenue), icon: Icons.payments, color: AppColors.secondary),
          KpiCard(label: 'Active Deliveries', value: '$_activeDeliveries', icon: Icons.delivery_dining, color: AppColors.warning),
          KpiCard(label: 'Suppliers', value: '$_suppliers', icon: Icons.storefront, color: const Color(0xFF6C5CE7)),
          KpiCard(label: 'Customers', value: '$_customers', icon: Icons.people, color: const Color(0xFF0984E3)),
        ]),
        const SizedBox(height: 24),
        AdminCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Orders — last 7 days', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 16),
              SizedBox(
                height: 220,
                child: LineChart(LineChartData(
                  titlesData: const FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      color: AppColors.primary,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(show: true, color: AppColors.primary.withOpacity(0.1)),
                      spots: [for (var i = 0; i < series.length; i++) FlSpot(i.toDouble(), series[i])],
                    ),
                  ],
                )),
              ),
            ]),
        ),
        const SizedBox(height: 24),
        AdminCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Recent Orders',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              const Divider(height: 1),
              if (_orders.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No orders yet', style: TextStyle(color: AppColors.textMuted)),
                ),
              ..._orders.take(10).map((o) => Column(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      child: Row(children: [
                        Expanded(
                          flex: 2,
                          child: Text('#${o.id.substring(0, 8)}',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(formatDate(o.placedAt),
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(formatRupees(o.total),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        StatusChip.order(o.status),
                      ]),
                    ),
                    const Divider(height: 1),
                  ])),
            ],
          ),
        ),
      ],
    );
  }
}
