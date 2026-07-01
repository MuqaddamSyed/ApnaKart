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
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
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

    final orders =
        await ref.read(orderServiceProvider).getSessionOrders(widget.sessionId);
    if (mounted) setState(() => _subOrders = orders);
  }

  Future<void> _call(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  Future<void> _accept() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(orderServiceProvider)
          .completeSessionDelivery(widget.sessionId);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reject() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(orderServiceProvider)
          .rejectSessionByCustomer(widget.sessionId);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel() async {
    // Cancel all sub-orders in the session.
    for (final o in _subOrders) {
      await ref
          .read(orderServiceProvider)
          .updateOrderStatus(o.id, OrderStatus.cancelled);
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
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final session = snap.data!;
          final agentLat = (_agent?['current_lat'] as num?)?.toDouble();
          final agentLng = (_agent?['current_lng'] as num?)?.toDouble();
          final isArrived = session.status == SessionStatus.out_for_delivery &&
              _subOrders.any((o) => o.status == OrderStatus.arrived);
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
              // Shops in this order.
              if (_subOrders.isNotEmpty) ...[
                const Text('Shops',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ..._subOrders.map((o) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.store,
                            color: AppColors.primary),
                        title: Text(o.supplierName ?? o.supplierId.substring(0, 8)),
                        subtitle: Text(o.status.label),
                      ),
                    )),
                const SizedBox(height: 8),
              ],
              // Delivery agent info.
              if (_agent != null)
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
              // Accept / Reject when agent has arrived.
              if (isArrived && !isDelivered && !isCancelled) ...[
                const SizedBox(height: 12),
                Card(
                  color: AppColors.warning.withOpacity(0.1),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(children: [
                      Icon(Icons.emoji_people, color: AppColors.warning),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Your delivery partner has arrived. Please collect your order and pay by cash.',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary),
                  icon: const Icon(Icons.check_circle),
                  label: const Text('I received my order'),
                  onPressed: _loading ? null : _accept,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger),
                  icon: const Icon(Icons.cancel),
                  label: const Text('Reject / Return'),
                  onPressed: _loading ? null : _reject,
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
                    onPressed: _cancel,
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
