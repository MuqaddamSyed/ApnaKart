import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/order_session.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';
import 'admin_ui.dart';

/// KPI cards + 7-day sessions line chart + live recent sessions.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});
  @override
  State<OverviewScreen> createState() => _State();
}

class _State extends State<OverviewScreen> {
  List<OrderSession> _sessions = [];
  int _suppliers = 0, _customers = 0, _activeSessions = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await supabase
        .from('order_sessions')
        .select()
        .order('placed_at', ascending: false);
    _sessions =
        (sessions as List).map((e) => OrderSession.fromMap(e)).toList();

    _suppliers = (await supabase.from('suppliers').select('id')).length;
    _customers = (await supabase.from('customers').select('id')).length;
    _activeSessions = _sessions
        .where((s) => [
              SessionStatus.all_confirmed,
              SessionStatus.out_for_delivery,
            ].contains(s.status))
        .length;

    if (mounted) setState(() => _loading = false);
  }

  List<double> _last7Days() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      return _sessions
          .where((s) =>
              s.placedAt.toLocal().year == day.year &&
              s.placedAt.toLocal().month == day.month &&
              s.placedAt.toLocal().day == day.day)
          .length
          .toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final now = DateTime.now();
    final todaySessions = _sessions.where((s) =>
        s.placedAt.toLocal().year == now.year &&
        s.placedAt.toLocal().month == now.month &&
        s.placedAt.toLocal().day == now.day);
    final revenue = todaySessions.fold<double>(0, (s, o) => s + o.total);
    final series = _last7Days();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const AdminPageTitle('Dashboard Overview'),
        Wrap(spacing: 16, runSpacing: 16, children: [
          KpiCard(
              label: 'Orders Today',
              value: '${todaySessions.length}',
              icon: Icons.shopping_bag,
              color: AppColors.primary),
          KpiCard(
              label: 'Revenue Today',
              value: formatRupees(revenue),
              icon: Icons.payments,
              color: AppColors.secondary),
          KpiCard(
              label: 'Active Deliveries',
              value: '$_activeSessions',
              icon: Icons.delivery_dining,
              color: AppColors.warning),
          KpiCard(
              label: 'Suppliers',
              value: '$_suppliers',
              icon: Icons.storefront,
              color: const Color(0xFF6C5CE7)),
          KpiCard(
              label: 'Customers',
              value: '$_customers',
              icon: Icons.people,
              color: const Color(0xFF0984E3)),
          KpiCard(
              label: 'Total Orders',
              value: '${_sessions.length}',
              icon: Icons.receipt_long,
              color: AppColors.textMuted),
        ]),
        const SizedBox(height: 24),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Orders — last 7 days',
                  style:
                      TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 16),
              SizedBox(
                height: 220,
                child: LineChart(LineChartData(
                  titlesData: const FlTitlesData(
                    leftTitles: AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: true, reservedSize: 28)),
                    topTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: true)),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      color: AppColors.primary,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                          show: true,
                          color: AppColors.primary.withOpacity(0.1)),
                      spots: [
                        for (var i = 0; i < series.length; i++)
                          FlSpot(i.toDouble(), series[i])
                      ],
                    ),
                  ],
                )),
              ),
            ],
          ),
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
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              const Divider(height: 1),
              if (_sessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No orders yet',
                      style: TextStyle(color: AppColors.textMuted)),
                ),
              ..._sessions.take(10).map((s) => Column(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      child: Row(children: [
                        Expanded(
                          flex: 2,
                          child: Text('#${s.shortId}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(formatDate(s.placedAt),
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 13)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(formatRupees(s.total),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                        ),
                        _sessionChip(s.status),
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

  Widget _sessionChip(SessionStatus s) {
    final (label, color) = switch (s) {
      SessionStatus.delivered => ('Delivered', AppColors.secondary),
      SessionStatus.cancelled => ('Cancelled', AppColors.danger),
      SessionStatus.out_for_delivery => ('Out for delivery', AppColors.primary),
      SessionStatus.all_confirmed => ('Confirmed', AppColors.warning),
      SessionStatus.waiting_suppliers => ('Waiting', AppColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
