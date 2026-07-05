import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';

/// Delivery earnings: Today/Week/Month tabs + per-delivery list.
class DeliveryEarningsScreen extends ConsumerStatefulWidget {
  const DeliveryEarningsScreen({super.key});
  @override
  ConsumerState<DeliveryEarningsScreen> createState() => _State();
}

class _State extends ConsumerState<DeliveryEarningsScreen> {
  int _range = 0;
  List<Map<String, dynamic>> _deliveries = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid != null) {
      // The agent's earning is the SESSION delivery fee (orders carry 0 —
      // the fee lives on the session in the multi-supplier model).
      final rows = await supabase.from('order_sessions')
          .select('id, display_id, delivery_fee, delivered_at')
          .eq('delivery_id', uid)
          .eq('status', 'delivered')
          .order('delivered_at', ascending: false);
      _deliveries = (rows as List).cast<Map<String, dynamic>>();
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    final now = DateTime.now();
    return _deliveries.where((d) {
      // delivered_at is UTC; compare in local time so "today" is the real day.
      final t = (DateTime.tryParse(d['delivered_at']?.toString() ?? '') ?? now)
          .toLocal();
      final diff = now.difference(t).inDays;
      if (_range == 0) {
        return t.year == now.year && t.month == now.month && t.day == now.day;
      }
      if (_range == 1) return diff < 7;
      return diff < 30;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final f = _filtered;
    final earnings = f.fold<double>(0, (s, d) => s + ((d['delivery_fee'] as num?)?.toDouble() ?? 0));
    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
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
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Text(formatRupees(earnings),
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    Text('${f.length} deliveries', style: const TextStyle(color: AppColors.textMuted)),
                  ]),
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  children: f.map((d) => ListTile(
                        title: Text(
                            '#${(d['display_id'] as String?) ?? d['id'].toString().substring(0, 8)}'),
                        trailing: Text(
                            formatRupees((d['delivery_fee'] as num?)?.toDouble() ?? 0),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      )).toList(),
                ),
              ),
            ]),
    );
  }
}
