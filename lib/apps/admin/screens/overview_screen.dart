import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../shared/models/order_session.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';
import 'admin_ui.dart';

/// Admin overview: KPI row, 7-day orders trend, status donut, pending
/// actions, top suppliers and recent orders.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});
  @override
  State<OverviewScreen> createState() => _State();
}

class _State extends State<OverviewScreen> {
  List<OrderSession> _sessions = [];
  int _suppliers = 0, _pendingSuppliers = 0, _customers = 0;
  int _agents = 0, _agentsOnline = 0, _activeSessions = 0;
  List<Map<String, dynamic>> _topSuppliers = [];
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
    _sessions = (sessions as List).map((e) => OrderSession.fromMap(e)).toList();

    final sup = await supabase.from('suppliers').select('id, is_verified');
    _suppliers = (sup as List).length;
    _pendingSuppliers =
        sup.where((s) => s['is_verified'] == false).length;

    _customers = (await supabase.from('customers').select('id')).length;

    final ag =
        await supabase.from('delivery_agents').select('id, is_available');
    _agents = (ag as List).length;
    _agentsOnline = ag.where((a) => a['is_available'] == true).length;

    _activeSessions = _sessions
        .where((s) => [
              SessionStatus.all_confirmed,
              SessionStatus.out_for_delivery,
            ].contains(s.status))
        .length;

    try {
      final top = await supabase
          .from('v_supplier_earnings')
          .select('supplier_name, lifetime_earnings, delivered_orders')
          .order('lifetime_earnings', ascending: false)
          .limit(5);
      _topSuppliers = (top as List).cast<Map<String, dynamic>>();
    } catch (_) {/* view may not be applied yet */}

    if (mounted) setState(() => _loading = false);
  }

  // ---- derived data ----
  List<double> _last7() {
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

  Map<SessionStatus, int> _statusCounts() {
    final m = <SessionStatus, int>{};
    for (final s in _sessions) {
      m[s.status] = (m[s.status] ?? 0) + 1;
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final now = DateTime.now();
    final today = _sessions.where((s) =>
        s.placedAt.toLocal().year == now.year &&
        s.placedAt.toLocal().month == now.month &&
        s.placedAt.toLocal().day == now.day);
    final revenueToday = today.fold<double>(0, (s, o) => s + o.total);

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const AdminPageTitle('Dashboard',
            subtitle: 'A live snapshot of orders, revenue and operations'),
        // KPI row
        Wrap(spacing: 16, runSpacing: 16, children: [
          KpiCard(
              label: 'Orders Today',
              value: '${today.length}',
              icon: Icons.shopping_bag_rounded,
              color: AdminTheme.chartBlue),
          KpiCard(
              label: 'Revenue Today',
              value: formatRupees(revenueToday),
              icon: Icons.payments_rounded,
              color: AdminTheme.cDelivered),
          KpiCard(
              label: 'Active Deliveries',
              value: '$_activeSessions',
              icon: Icons.local_shipping_rounded,
              color: AdminTheme.cWaiting),
          KpiCard(
              label: 'Suppliers',
              value: '$_suppliers',
              icon: Icons.storefront_rounded,
              color: const Color(0xFF6C5CE7),
              subtitle:
                  _pendingSuppliers > 0 ? '$_pendingSuppliers pending' : null),
          KpiCard(
              label: 'Delivery Agents',
              value: '$_agents',
              icon: Icons.delivery_dining_rounded,
              color: AdminTheme.accent,
              subtitle: _agentsOnline > 0 ? '$_agentsOnline online' : null),
          KpiCard(
              label: 'Customers',
              value: '$_customers',
              icon: Icons.people_alt_rounded,
              color: const Color(0xFF0984E3)),
        ]),
        const SizedBox(height: 24),
        // Trend + donut
        LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth > 900;
          final trend = _trendCard();
          final donut = _statusCard();
          if (!wide) {
            return Column(children: [
              trend,
              const SizedBox(height: 24),
              donut,
            ]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: trend),
              const SizedBox(width: 24),
              Expanded(flex: 2, child: donut),
            ],
          );
        }),
        const SizedBox(height: 24),
        // Recent orders + right column
        LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth > 900;
          final recent = _recentOrdersCard();
          final side = Column(children: [
            _pendingCard(),
            const SizedBox(height: 24),
            _topSuppliersCard(),
          ]);
          if (!wide) {
            return Column(children: [
              recent,
              const SizedBox(height: 24),
              side,
            ]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: recent),
              const SizedBox(width: 24),
              Expanded(flex: 2, child: side),
            ],
          );
        }),
      ],
    );
  }

  // ---------------- Trend ----------------
  Widget _trendCard() {
    final series = _last7();
    final maxY = (series.isEmpty ? 0 : series.reduce((a, b) => a > b ? a : b));
    final now = DateTime.now();
    const dayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return SectionCard(
      title: 'Orders — last 7 days',
      subtitle: 'Order sessions placed per day',
      child: SizedBox(
        height: 240,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: (maxY < 4 ? 4 : maxY + 1).toDouble(),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 1,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: AdminTheme.border, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 30)),
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i > 6) return const SizedBox.shrink();
                    final d = now.subtract(Duration(days: 6 - i));
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(dayLabels[d.weekday % 7],
                          style: const TextStyle(
                              fontSize: 12, color: AdminTheme.inkMuted)),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                tooltipBgColor: AdminTheme.ink,
                getTooltipItems: (spots) => spots
                    .map((s) => LineTooltipItem(
                        '${s.y.toInt()} orders',
                        const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600)))
                    .toList(),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                isCurved: true,
                curveSmoothness: 0.28,
                color: AdminTheme.chartBlue,
                barWidth: 3,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                      radius: 4,
                      color: Colors.white,
                      strokeWidth: 2.5,
                      strokeColor: AdminTheme.chartBlue),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AdminTheme.chartBlue.withOpacity(0.22),
                      AdminTheme.chartBlue.withOpacity(0.0),
                    ],
                  ),
                ),
                spots: [
                  for (var i = 0; i < series.length; i++)
                    FlSpot(i.toDouble(), series[i]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- Status donut ----------------
  static const _statusMeta = <SessionStatus, (String, Color)>{
    SessionStatus.delivered: ('Delivered', AdminTheme.cDelivered),
    SessionStatus.out_for_delivery:
        ('Out for delivery', AdminTheme.cOutForDelivery),
    SessionStatus.all_confirmed: ('Confirmed', AdminTheme.cConfirmed),
    SessionStatus.waiting_suppliers: ('Waiting', AdminTheme.cWaiting),
    SessionStatus.cancelled: ('Cancelled', AdminTheme.cCancelled),
  };

  Widget _statusCard() {
    final counts = _statusCounts();
    final total = _sessions.length;
    return SectionCard(
      title: 'Order status',
      subtitle: '$total orders all-time',
      child: SizedBox(
        height: 240,
        child: total == 0
            ? const Center(
                child: Text('No orders yet',
                    style: TextStyle(color: AdminTheme.inkMuted)))
            : Row(
                children: [
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 46,
                        sections: [
                          for (final e in _statusMeta.entries)
                            if ((counts[e.key] ?? 0) > 0)
                              PieChartSectionData(
                                value: (counts[e.key] ?? 0).toDouble(),
                                color: e.value.$2,
                                radius: 34,
                                showTitle: false,
                              ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in _statusMeta.entries)
                        if ((counts[e.key] ?? 0) > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                      color: e.value.$2,
                                      borderRadius:
                                          BorderRadius.circular(3))),
                              const SizedBox(width: 8),
                              Text('${e.value.$1}',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AdminTheme.inkMuted)),
                              const SizedBox(width: 6),
                              Text('${counts[e.key]}',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: AdminTheme.ink)),
                            ]),
                          ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  // ---------------- Pending actions ----------------
  Widget _pendingCard() {
    final waiting = _sessions
        .where((s) => s.status == SessionStatus.waiting_suppliers)
        .length;
    final unassigned = _sessions
        .where((s) =>
            s.status == SessionStatus.all_confirmed && s.deliveryId == null)
        .length;
    Widget row(IconData i, Color c, String label, int n) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: c.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(i, color: c, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13.5, color: AdminTheme.ink))),
            Text('$n',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: c)),
          ]),
        );
    return SectionCard(
      title: 'Needs attention',
      child: Column(children: [
        row(Icons.verified_user_rounded, const Color(0xFF6C5CE7),
            'Suppliers awaiting verification', _pendingSuppliers),
        row(Icons.hourglass_bottom_rounded, AdminTheme.cWaiting,
            'Orders waiting on shops', waiting),
        row(Icons.local_shipping_rounded, AdminTheme.chartBlue,
            'Orders needing an agent', unassigned),
        row(Icons.wifi_tethering_rounded, AdminTheme.cDelivered,
            'Agents online now', _agentsOnline),
      ]),
    );
  }

  // ---------------- Top suppliers ----------------
  Widget _topSuppliersCard() {
    return SectionCard(
      title: 'Top suppliers',
      subtitle: 'By lifetime delivered revenue',
      child: _topSuppliers.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No sales yet',
                  style: TextStyle(color: AdminTheme.inkMuted)),
            )
          : Column(
              children: [
                for (var i = 0; i < _topSuppliers.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: AdminTheme.bg,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: AdminTheme.inkMuted)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                            (_topSuppliers[i]['supplier_name'] as String?) ??
                                'Shop',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AdminTheme.ink)),
                      ),
                      Text(
                          formatRupees(
                              (_topSuppliers[i]['lifetime_earnings'] as num?)
                                      ?.toDouble() ??
                                  0),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AdminTheme.cDelivered)),
                    ]),
                  ),
              ],
            ),
    );
  }

  // ---------------- Recent orders ----------------
  Widget _recentOrdersCard() {
    final recent = _sessions.take(8).toList();
    return SectionCard(
      title: 'Recent orders',
      child: recent.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                  child: Text('No orders yet',
                      style: TextStyle(color: AdminTheme.inkMuted))),
            )
          : Column(
              children: [
                for (final s in recent) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Expanded(
                        flex: 2,
                        child: Text('#${s.shortId}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AdminTheme.ink)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(formatDate(s.placedAt),
                            style: const TextStyle(
                                color: AdminTheme.inkMuted, fontSize: 12.5)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(formatRupees(s.total),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AdminTheme.ink)),
                      ),
                      _chip(s.status),
                    ]),
                  ),
                  if (s != recent.last)
                    const Divider(height: 1, color: AdminTheme.border),
                ],
              ],
            ),
    );
  }

  Widget _chip(SessionStatus s) {
    final meta = _statusMeta[s] ?? ('—', AdminTheme.inkMuted);
    return StatusChip(meta.$1, meta.$2);
  }
}
