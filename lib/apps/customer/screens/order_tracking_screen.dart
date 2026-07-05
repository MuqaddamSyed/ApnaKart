import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_session.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';

/// Live tracking screen for a session (multi-supplier order).
/// Shows status stepper, OSM map with agent location, and
/// Accept/Reject buttons when the agent arrives.
class OrderTrackingScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const OrderTrackingScreen({super.key, required this.sessionId});
  @override
  ConsumerState<OrderTrackingScreen> createState() => _State();
}

class _State extends ConsumerState<OrderTrackingScreen> {
  Map<String, dynamic>? _agent;
  List<Order> _subOrders = [];
  // supplierId -> phone, for self-delivered orders (the shop is the deliverer).
  Map<String, String> _shopPhones = {};
  // Live status per sub-order id, driven by the realtime stream (which lacks
  // the supplier-name joins that _subOrders carries for display).
  Map<String, OrderStatus> _liveStatus = {};
  bool _loading = false;
  Timer? _agentTimer;
  StreamSubscription<List<Order>>? _subOrdersSub;

  @override
  void initState() {
    super.initState();
    _loadDetails();
    // Live sub-order updates so arrival/status reflects the delivery agent.
    _subOrdersSub = ref
        .read(orderServiceProvider)
        .listenToSessionOrders(widget.sessionId)
        .listen((orders) {
      if (mounted && orders.isNotEmpty) {
        setState(() {
          _liveStatus = {for (final o in orders) o.id: o.status};
        });
      }
    });
    // Poll the agent's live location every 15s for map + ETA.
    _agentTimer = Timer.periodic(
        const Duration(seconds: 15), (_) => _loadAgent());
  }

  @override
  void dispose() {
    _agentTimer?.cancel();
    _subOrdersSub?.cancel();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    await _loadAgent();
    // Initial sub-order snapshot with supplier names/joins for display.
    final orders =
        await ref.read(orderServiceProvider).getSessionOrders(widget.sessionId);
    if (mounted && orders.isNotEmpty) {
      setState(() {
        _subOrders = orders;
        _liveStatus = {for (final o in orders) o.id: o.status};
      });
    }
    // For a self-delivered order, fetch the delivering shop's phone.
    final contacts =
        await ref.read(orderServiceProvider).getSessionContacts(widget.sessionId);
    if (mounted && contacts.supplierPhones.isNotEmpty) {
      setState(() => _shopPhones = contacts.supplierPhones);
    }
  }

  Future<void> _loadAgent() async {
    final session = await supabase
        .from('order_sessions')
        .select('delivery_id')
        .eq('id', widget.sessionId)
        .maybeSingle();

    if (session?['delivery_id'] != null) {
      final a = await supabase
          .from('delivery_agents')
          .select('current_lat,current_lng,users(name,phone)')
          .eq('id', session!['delivery_id'])
          .maybeSingle();
      if (mounted) setState(() => _agent = a);
    }
  }

  Future<void> _call(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the dialer')),
      );
    }
  }


  Future<void> _cancel() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(orderServiceProvider)
          .cancelSessionByCustomer(widget.sessionId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // AppBar with back button (context.push preserves stack).
      appBar: AppBar(title: const Text('Track Order')),
      body: StreamBuilder<OrderSession>(
        stream: ref
            .read(orderServiceProvider)
            .listenToSession(widget.sessionId),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load order: ${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted)),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final session = snap.data!;
          final agentLat = (_agent?['current_lat'] as num?)?.toDouble();
          final agentLng = (_agent?['current_lng'] as num?)?.toDouble();
          // Use live status map so isArrived updates without re-fetching.
          final isArrived = session.status == SessionStatus.out_for_delivery &&
              _liveStatus.values.any((s) => s == OrderStatus.arrived);
          final isDelivered = session.status == SessionStatus.delivered;
          final isCancelled = session.status == SessionStatus.cancelled;

          int? etaMin;
          if (session.status == SessionStatus.out_for_delivery &&
              agentLat != null &&
              agentLng != null &&
              session.deliveryLat != null &&
              session.deliveryLng != null) {
            final loc = ref.read(locationServiceProvider);
            final km = loc.calculateDistance(agentLat, agentLng,
                session.deliveryLat!, session.deliveryLng!);
            etaMin = loc.etaMinutes(km);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Order ID + status chip.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Order #${session.shortId}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(session.status).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      session.status.label,
                      style: TextStyle(
                          color: _statusColor(session.status),
                          fontWeight: FontWeight.w600,
                          fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Map.
              SizedBox(
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter:
                          LatLng(agentLat ?? 14.4644, agentLng ?? 75.9218),
                      initialZoom: 14,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.quickkart.customer',
                      ),
                      MarkerLayer(markers: [
                        if (agentLat != null && agentLng != null)
                          Marker(
                            point: LatLng(agentLat, agentLng),
                            child: const Icon(Icons.delivery_dining,
                                color: AppColors.primary, size: 36),
                          ),
                        if (session.deliveryLat != null &&
                            session.deliveryLng != null)
                          Marker(
                            point: LatLng(
                                session.deliveryLat!, session.deliveryLng!),
                            child: const Icon(Icons.home,
                                color: AppColors.secondary, size: 32),
                          ),
                      ]),
                    ],
                  ),
                ),
              ),
              if (etaMin != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Card(
                    color: AppColors.secondary.withOpacity(0.1),
                    child: ListTile(
                      leading: const Icon(Icons.schedule,
                          color: AppColors.secondary),
                      title: Text('Arriving in about $etaMin min'),
                      subtitle: const Text('Agent is on the way'),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              // Shops in this order — show live status.
              if (_subOrders.isNotEmpty) ...[
                const Text('Shops',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ..._subOrders.map((o) {
                  final status = _liveStatus[o.id] ?? o.status;
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.store,
                          color: AppColors.primary),
                      title: Text(o.supplierName ?? _shortId(o.supplierId)),
                      subtitle: Text(status.label),
                    ),
                  );
                }),
                const SizedBox(height: 8),
              ],
              // Self-delivery: the shop delivers the order itself.
              if (session.deliveryMode == 'self' && _subOrders.isNotEmpty)
                Builder(builder: (context) {
                  final shop = _subOrders.first;
                  final phone = _shopPhones[shop.supplierId];
                  return Card(
                    color: AppColors.primary.withOpacity(0.06),
                    child: ListTile(
                      leading: const Icon(Icons.storefront,
                          color: AppColors.primary),
                      title: Text(
                          'Delivered by ${shop.supplierName ?? 'the shop'}'),
                      subtitle: Text(
                          phone != null ? phone : 'The shop is delivering your order'),
                      trailing: phone != null
                          ? IconButton(
                              icon: const Icon(Icons.call,
                                  color: AppColors.secondary),
                              tooltip: 'Call shop',
                              onPressed: () => _call(phone),
                            )
                          : null,
                    ),
                  );
                })
              // Delivery agent info.
              else if (_agent != null)
                Card(
                  child: ListTile(
                    leading:
                        const Icon(Icons.person, color: AppColors.primary),
                    title: Text(
                        _agent?['users']?['name'] ?? 'Delivery partner'),
                    subtitle: const Text('Tap to call'),
                    trailing: IconButton(
                      icon: const Icon(Icons.call, color: AppColors.secondary),
                      onPressed: () =>
                          _call(_agent?['users']?['phone'] as String?),
                    ),
                  ),
                ),
              // At the door: show the handoff code + reject option.
              // The agent enters this code to confirm delivery (works even
              // if you background the app — just read it out).
              if (isArrived && !isDelivered && !isCancelled) ...[
                const SizedBox(height: 12),
                Card(
                  color: AppColors.secondary.withOpacity(0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Your delivery partner has arrived',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        const Text(
                          'Collect your order, pay by cash, and share this code with the partner to confirm delivery:',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textMuted),
                        ),
                        const SizedBox(height: 12),
                        FutureBuilder<String?>(
                          future: ref
                              .read(orderServiceProvider)
                              .getSessionOtp(widget.sessionId),
                          builder: (context, s) => Center(
                            child: Text(
                              s.data ?? '– – – –',
                              style: const TextStyle(
                                  fontSize: 40,
                                  letterSpacing: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.secondary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              // Delivered state.
              if (isDelivered)
                Card(
                  color: AppColors.secondary.withOpacity(0.1),
                  child: const ListTile(
                    leading: Icon(Icons.check_circle,
                        color: AppColors.secondary),
                    title: Text('Order delivered!',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Thank you for your order.'),
                  ),
                ),
              // Cancel option (only while still placed).
              if (session.status == SessionStatus.waiting_suppliers)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton(
                    onPressed: _loading ? null : _cancel,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger),
                    child: const Text('Cancel Order'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _shortId(String id) =>
      id.length >= 8 ? id.substring(0, 8) : id;

  Color _statusColor(SessionStatus s) {
    switch (s) {
      case SessionStatus.waiting_suppliers: return AppColors.warning;
      case SessionStatus.all_confirmed: return AppColors.primary;
      case SessionStatus.out_for_delivery: return AppColors.primary;
      case SessionStatus.delivered: return AppColors.secondary;
      case SessionStatus.cancelled: return AppColors.danger;
    }
  }
}
