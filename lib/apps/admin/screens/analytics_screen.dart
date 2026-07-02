import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/order_session.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';
import 'admin_ui.dart';

/// Revenue by supplier (shop name), peak-hours bar chart, session totals.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _State();
}

class _State extends State<AnalyticsScreen> {
  List<OrderSession> _sessions = [];
  // supplierId -> {shopName, revenue}
  Map<String, _SupplierRevenue> _bySupplier = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // Load sessions for peak-hours + total revenue.
    final sessionRows = await supabase
        .from('order_sessions')
        .select()
        .eq('status', 'delivered');
    _sessions = (sessionRows as List)
        .map((e) => OrderSession.fromMap(e))
        .toList();

    // Load sub-orders joined with supplier shop names.
    final orderRows = await supabase
        .from('orders')
        .select('supplier_id, subtotal, suppliers(shop_name)')
        .eq('status', 'delivered');
    final map = <String, _SupplierRevenue>{};
    for (final row in (orderRows as List)) {
      final sid = row['supplier_id'] as String;
      final subtotal = (row['subtotal'] as num?)?.toDouble() ?? 0;
      final shopName = (row['suppliers'] as Map?)?['shop_name'] as String?
          ?? sid.substring(0, 8);
      map[sid] = _SupplierRevenue(
        shopName: shopName,
        revenue: (map[sid]?.revenue ?? 0) + subtotal,
      );
    }
    // Sort descending by revenue.
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.revenue.compareTo(a.value.revenue));
    _bySupplier = Map.fromEntries(sorted);

    if (mounted) setState(() => _loading = false);
  }

  List<double> _peakHours() {
    final buckets = List<double>.filled(24, 0);
    for (final s in _sessions) {
      buckets[s.placedAt.hour] += 1;
    }
    return buckets;
  }

  double get _totalRevenue =>
      _sessions.fold(0, (s, o) => s + o.total);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final hours = _peakHours();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        AdminPageTitle(
          'Analytics',
          trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ),
        // Summary KPIs.
        Wrap(spacing: 16, runSpacing: 16, children: [
          KpiCard(
            label: 'Total Revenue',
            value: formatRupees(_totalRevenue),
            icon: Icons.payments,
            color: AppColors.secondary,
          ),
          KpiCard(
            label: 'Delivered Orders',
            value: '${_sessions.length}',
            icon: Icons.check_circle_outline,
            color: AppColors.primary,
          ),
          KpiCard(
            label: 'Active Suppliers',
            value: '${_bySupplier.length}',
            icon: Icons.storefront,
            color: const Color(0xFF6C5CE7),
          ),
        ]),
        const SizedBox(height: 24),
        // Peak hours bar chart.
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Peak Ordering Hours',
                  style:
                      TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 16),
              SizedBox(
                height: 220,
                child: BarChart(BarChartData(
                  titlesData: const FlTitlesData(
                    leftTitles: AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: true, reservedSize: 28)),
                    topTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                            showTitles: true, reservedSize: 20)),
                  ),
                  barGroups: [
                    for (var h = 0; h < 24; h++)
                      BarChartGroupData(x: h, barRods: [
                        BarChartRodData(
                            toY: hours[h],
                            color: AppColors.primary,
                            width: 6),
                      ]),
                  ],
                )),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Revenue by supplier.
        AdminCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Revenue by Supplier',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              const Divider(height: 1),
              if (_bySupplier.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No delivered orders yet',
                      style: TextStyle(color: AppColors.textMuted)),
                ),
              ..._bySupplier.values.map((s) => Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        child: Row(children: [
                          const Icon(Icons.storefront,
                              size: 18, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(s.shopName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                          Text(formatRupees(s.revenue),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.secondary)),
                        ]),
                      ),
                      const Divider(height: 1),
                    ],
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

class _SupplierRevenue {
  final String shopName;
  final double revenue;
  const _SupplierRevenue({required this.shopName, required this.revenue});
}
