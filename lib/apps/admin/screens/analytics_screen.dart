import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/order.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';

/// Revenue by supplier, top products, peak hours bar chart.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _State();
}

class _State extends State<AnalyticsScreen> {
  List<Order> _orders = [];
  Map<String, double> _revenueBySupplier = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final rows = await supabase.from('orders').select();
    _orders = (rows as List).map((e) => Order.fromMap(e)).toList();
    for (final o in _orders) {
      _revenueBySupplier[o.supplierId] =
          (_revenueBySupplier[o.supplierId] ?? 0) + o.total;
    }
    setState(() => _loading = false);
  }

  List<double> _peakHours() {
    final buckets = List<double>.filled(24, 0);
    for (final o in _orders) {
      buckets[o.placedAt.hour] += 1;
    }
    return buckets;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final hours = _peakHours();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Analytics', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Peak Ordering Hours', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              SizedBox(
                height: 220,
                child: BarChart(BarChartData(
                  titlesData: const FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 20)),
                  ),
                  barGroups: [
                    for (var h = 0; h < 24; h++)
                      BarChartGroupData(x: h, barRods: [
                        BarChartRodData(toY: hours[h], color: AppColors.primary, width: 6),
                      ]),
                  ],
                )),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Revenue by Supplier', style: TextStyle(fontWeight: FontWeight.w700)),
        ..._revenueBySupplier.entries.map((e) => Card(
              child: ListTile(
                title: Text('Supplier ${e.key.substring(0, 8)}'),
                trailing: Text(formatRupees(e.value),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            )),
      ],
    );
  }
}
