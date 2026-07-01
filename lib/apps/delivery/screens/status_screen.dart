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

  @override
  void initState() {
    super.initState();
    _load();
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
      setState(() {});
    }
  }

  Future<void> _toggle(bool v) async {
    final uid = supabase.auth.currentUser?.id;
    if (!_approved) return;
    setState(() => _online = v);
    if (uid != null) {
      await supabase
          .from('delivery_agents')
          .update({'is_available': v})
          .eq('id', uid);
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
          const SizedBox(height: 16),
          const Text('Available Requests',
              style: TextStyle(fontWeight: FontWeight.w700)),
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
          else
            StreamBuilder<List<OrderSession>>(
              stream: ref
                  .read(orderServiceProvider)
                  .listenToAvailableSessions(),
              builder: (context, snap) {
                final sessions = snap.data ?? [];
                if (sessions.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No requests right now')),
                  );
                }
                return Column(
                  children: sessions
                      .map((s) => Card(
                            child: ListTile(
                              leading: const Icon(Icons.shopping_bag,
                                  color: AppColors.primary),
                              title: Text('Order #${s.shortId}'),
                              subtitle: Text(
                                  '${s.subOrders.isEmpty ? '' : s.subOrders.length.toString() + ' shop(s) · '}${s.deliveryAddress ?? ''}'),
                              trailing: ElevatedButton(
                                child: const Text('View'),
                                onPressed: () => showModalBottomSheet(
                                  context: context,
                                  builder: (_) =>
                                      IncomingOrderSheet(session: s),
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                );
              },
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
