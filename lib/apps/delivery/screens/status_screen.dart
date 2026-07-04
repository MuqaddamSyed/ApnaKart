import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/delivery_agent.dart';
import '../../../shared/models/order_session.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';
import 'incoming_order_sheet.dart';

/// Online/offline toggle, today's stats, available delivery sessions.
class StatusScreen extends ConsumerStatefulWidget {
  const StatusScreen({super.key});
  @override
  ConsumerState<StatusScreen> createState() => _State();
}

class _State extends ConsumerState<StatusScreen> {
  bool _online = false;
  bool _approved = false;
  DeliveryAgent? _agent;
  double _codTotal = 0; // total COD cash collected across all deliveries
  // The available-delivery pool is fetched (not realtime-only) so a realtime
  // hiccup can't leave the agent staring at an empty screen while a job waits.
  List<OrderSession> _sessions = [];
  bool _loadingPool = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // Refresh stats (deliveries / earnings / COD) + the pool every 10s, so the
    // dashboard reflects a completed delivery without needing a manual reload.
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_approved) _refreshStats();
      if (_approved && _online) _refreshPool();
    });
  }

  Future<void> _refreshStats() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await supabase
          .from('delivery_agents')
          .select()
          .eq('id', uid)
          .maybeSingle();
      final cod = await ref.read(orderServiceProvider).getAgentCodTotal(uid);
      if (mounted) {
        setState(() {
          if (row != null) _agent = DeliveryAgent.fromMap(row);
          _codTotal = cod;
        });
      }
    } catch (_) {/* keep last known values on a transient failure */}
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid != null) {
      final row = await supabase
          .from('delivery_agents')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (row != null) {
        _agent = DeliveryAgent.fromMap(row);
        _online = _agent!.isAvailable;
        _approved = _agent!.isVerified;
      } else {
        await supabase.from('delivery_agents').insert({
          'id': uid,
          'is_available': false,
          'is_verified': false,
        });
        _approved = false;
      }
      if (_approved) {
        try {
          _codTotal =
              await ref.read(orderServiceProvider).getAgentCodTotal(uid);
        } catch (_) {/* RPC from migration 18; leave 0 if unavailable */}
      }
      if (mounted) setState(() {});
      if (_approved && _online) _refreshPool();
    }
  }

  Future<void> _refreshPool() async {
    if (!_approved || !_online) {
      if (_sessions.isNotEmpty && mounted) setState(() => _sessions = []);
      return;
    }
    if (_loadingPool) return;
    _loadingPool = true;
    try {
      final sessions = await ref.read(orderServiceProvider).getAvailableSessions();
      if (mounted) setState(() => _sessions = sessions);
    } catch (_) {
      // Keep the last known list on a transient failure.
    } finally {
      _loadingPool = false;
    }
  }

  Future<void> _toggle(bool v) async {
    final uid = supabase.auth.currentUser?.id;
    if (!_approved || uid == null) return;
    setState(() => _online = v);
    try {
      await supabase
          .from('delivery_agents')
          .update({'is_available': v})
          .eq('id', uid);
      if (v) {
        _refreshPool();
      } else if (mounted) {
        setState(() => _sessions = []);
      }
    } catch (e) {
      // Revert on failure so the UI reflects the real DB state.
      if (mounted) {
        setState(() => _online = !v);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update status: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_approved)
            Card(
              color: AppColors.warning.withOpacity(0.1),
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.verified_user_outlined,
                        color: AppColors.warning, size: 44),
                    SizedBox(height: 12),
                    Text('Waiting for admin approval',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    SizedBox(height: 8),
                    Text(
                      'Your delivery account is registered. You can go online after admin verification.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          if (!_approved) const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Text(_online ? 'You are Online' : 'You are Offline',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Switch(
                  value: _approved && _online,
                  activeColor: AppColors.secondary,
                  onChanged: _approved ? _toggle : null,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _stat('Deliveries', '${_agent?.totalDeliveries ?? 0}'),
            _stat('Earnings Today', formatRupees(_agent?.earningsToday ?? 0)),
          ]),
          const SizedBox(height: 12),
          // COD money the agent is accountable for (cash collected on delivery).
          Card(
            color: AppColors.primary.withOpacity(0.06),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.account_balance_wallet,
                    color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatRupees(_codTotal),
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800)),
                      const Text('Total COD collected',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(
              child: Text('Available Requests',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (_approved && _online)
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Refresh',
                onPressed: _refreshPool,
              ),
          ]),
          if (!_approved)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Approval pending')),
            )
          else if (!_online)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Go online to receive requests')),
            )
          else if (_sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No requests right now')),
            )
          else
            Column(
              children: _sessions
                  .map((s) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.shopping_bag,
                              color: AppColors.primary),
                          title: Text('Order #${s.shortId}'),
                          subtitle: FutureBuilder<int>(
                            future: ref
                                .read(orderServiceProvider)
                                .getSessionShopCount(s.id),
                            builder: (context, countSnap) {
                              final count = countSnap.data;
                              final prefix = count == null
                                  ? ''
                                  : '$count shop${count == 1 ? '' : 's'} · ';
                              return Text('$prefix${s.deliveryAddress ?? ''}');
                            },
                          ),
                          trailing: ElevatedButton(
                            child: const Text('View'),
                            onPressed: () async {
                              await showModalBottomSheet(
                                context: context,
                                builder: (_) => IncomingOrderSheet(session: s),
                              );
                              _refreshPool(); // re-sync after accept/decline
                            },
                          ),
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _stat(String l, String v) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Text(v,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
              Text(l,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textMuted)),
            ]),
          ),
        ),
      );
}
