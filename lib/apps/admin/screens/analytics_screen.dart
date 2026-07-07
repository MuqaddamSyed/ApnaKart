import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../shared/models/order_session.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';
import 'admin_ui.dart';

/// Revenue KPIs, peak-hours chart and revenue-by-supplier breakdown.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _State();
}

class _State extends State<AnalyticsScreen> {
  List<OrderSession> _delivered = [];
  Map<String, _SupplierRevenue> _bySupplier = {};
  int _totalSessions = 0, _cancelled = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      // Full select so OrderSession.fromMap has every field it needs.
      final all = await supabase.from('order_sessions').select();
      final list = (all as List);
      _totalSessions = list.length;
      _cancelled = list.where((s) => s['status'] == 'cancelled').length;
      _delivered = list
          .where((s) => s['status'] == 'delivered')
          .map((e) => OrderSession.fromMap(Map<String, dynamic>.from(e)))
          .toList();

      final orderRows = await supabase
          .from('orders')
          .select('supplier_id, subtotal, suppliers(shop_name)')
          .eq('status', 'delivered');
      final map = <String, _SupplierRevenue>{};
      for (final row in (orderRows as List)) {
        final sid = row['supplier_id'] as String;
        final subtotal = (row['subtotal'] as num?)?.toDouble() ?? 0;
        final shopName = (row['suppliers'] as Map?)?['shop_name'] as String? ??
            'Shop ${sid.substring(0, 4)}';
        map[sid] = _SupplierRevenue(
          shopName: shopName,
          revenue: (map[sid]?.revenue ?? 0) + subtotal,
        );
      }
      final sorted = map.entries.toList()
        ..sort((a, b) => b.value.revenue.compareTo(a.value.revenue));
      _bySupplier = Map.fromEntries(sorted);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load analytics: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<double> _peakHours() {
    final buckets = List<double>.filled(24, 0);
    for (final s in _delivered) {
      buckets[s.placedAt.toLocal().hour] += 1;
    }
    return buckets;
  }

  double get _revenue => _delivered.fold(0, (s, o) => s + o.total);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final aov = _delivered.isEmpty ? 0.0 : _revenue / _delivered.length;
    final cancelRate =
        _totalSessions == 0 ? 0 : (_cancelled / _totalSessions * 100).round();

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        AdminPageTitle(
          'Analytics',
          subtitle: 'Revenue, demand patterns and supplier performance',
          trailing: AdminIconButton(
              icon: Icons.refresh_rounded, tooltip: 'Refresh', onPressed: _load),
        ),
        Wrap(spacing: 16, runSpacing: 16, children: [
          KpiCard(
              label: 'Total Revenue',
              value: formatRupees(_revenue),
              icon: Icons.payments_rounded,
              color: AdminTheme.cDelivered),
          KpiCard(
              label: 'Delivered Orders',
              value: '${_delivered.length}',
              icon: Icons.check_circle_rounded,
              color: AdminTheme.chartBlue),
          KpiCard(
              label: 'Avg Order Value',
              value: formatRupees(aov),
              icon: Icons.receipt_long_rounded,
              color: const Color(0xFF6C5CE7)),
          KpiCard(
              label: 'Cancelled',
              value: '$_cancelled',
              icon: Icons.cancel_rounded,
              color: AdminTheme.cCancelled,
              subtitle: '$cancelRate% of orders'),
          KpiCard(
              label: 'Selling Shops',
              value: '${_bySupplier.length}',
              icon: Icons.storefront_rounded,
              color: AdminTheme.accent),
        ]),
        const SizedBox(height: 24),
        _peakHoursCard(),
        const SizedBox(height: 24),
        _revenueBySupplierCard(),
      ],
    );
  }

  Widget _peakHoursCard() {
    final hours = _peakHours();
    final maxY = hours.fold<double>(0, (m, v) => v > m ? v : m);
    return SectionCard(
      title: 'Peak ordering hours',
      subtitle: 'When customers place orders (local time)',
      child: SizedBox(
        height: 240,
        child: BarChart(
          BarChartData(
            maxY: (maxY < 3 ? 3 : maxY + 1),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: AdminTheme.border, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                tooltipBgColor: AdminTheme.ink,
                getTooltipItem: (g, _, r, __) => BarTooltipItem(
                  '${g.x}:00\n${r.toY.toInt()} orders',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 30)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (v, _) {
                    final h = v.toInt();
                    if (h % 4 != 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${h}h',
                          style: const TextStyle(
                              fontSize: 11, color: AdminTheme.inkMuted)),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (var h = 0; h < 24; h++)
                BarChartGroupData(x: h, barRods: [
                  BarChartRodData(
                    toY: hours[h],
                    color: AdminTheme.chartBlue,
                    width: 8,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4)),
                  ),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _revenueBySupplierCard() {
    final top = _bySupplier.values.take(8).toList();
    final maxRev = top.isEmpty
        ? 1.0
        : top.map((e) => e.revenue).reduce((a, b) => a > b ? a : b);
    return SectionCard(
      title: 'Revenue by supplier',
      subtitle: 'Delivered goods revenue (excludes delivery fee)',
      child: top.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No delivered orders yet',
                  style: TextStyle(color: AdminTheme.inkMuted)))
          : Column(
              children: [
                for (final s in top)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(s.shopName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                    color: AdminTheme.ink)),
                          ),
                          Text(formatRupees(s.revenue),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AdminTheme.cDelivered)),
                        ]),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (s.revenue / maxRev).clamp(0.02, 1.0),
                            minHeight: 8,
                            backgroundColor: AdminTheme.bg,
                            valueColor: const AlwaysStoppedAnimation(
                                AdminTheme.chartBlue),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _SupplierRevenue {
  final String shopName;
  final double revenue;
  const _SupplierRevenue({required this.shopName, required this.revenue});
}
