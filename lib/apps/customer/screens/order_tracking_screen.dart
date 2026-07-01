import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/order.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/services/otp_store.dart';
import '../../../shared/widgets/status_stepper.dart';

/// Live tracking: status stepper, OSM map with agent location, OTP, cancel.
class OrderTrackingScreen extends ConsumerStatefulWidget {
  final String orderId;
  const OrderTrackingScreen({super.key, required this.orderId});
  @override
  ConsumerState<OrderTrackingScreen> createState() => _State();
}

class _State extends ConsumerState<OrderTrackingScreen> {
  String? _otp;
  Map<String, dynamic>? _agent;

  @override
  void initState() {
    super.initState();
    _loadOtpAndAgent();
  }

  Future<void> _loadOtpAndAgent() async {
    // OTP is read from local storage — the server only keeps a hash.
    final localOtp = await OtpStore.get(widget.orderId);
    setState(() => _otp = localOtp);
    final row = await supabase.from('orders')
        .select('delivery_id').eq('id', widget.orderId).maybeSingle();
    if (row?['delivery_id'] != null) {
      final a = await supabase.from('delivery_agents')
          .select('current_lat,current_lng, users(name, phone)')
          .eq('id', row!['delivery_id']).maybeSingle();
      setState(() => _agent = a);
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  Future<void> _cancel() async {
    await ref.read(orderServiceProvider).updateOrderStatus(widget.orderId, OrderStatus.cancelled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Track Order')),
      body: StreamBuilder<Order>(
        stream: ref.read(orderServiceProvider).listenToOrder(widget.orderId),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final order = snap.data!;
          final agentLat = (_agent?['current_lat'] as num?)?.toDouble();
          final agentLng = (_agent?['current_lng'] as num?)?.toDouble();
          final atDoor = order.status == OrderStatus.on_the_way;
          // Free ETA via haversine between the agent and the delivery address.
          int? etaMin;
          if (atDoor && agentLat != null && agentLng != null &&
              order.deliveryLat != null && order.deliveryLng != null) {
            final loc = ref.read(locationServiceProvider);
            final km = loc.calculateDistance(
                agentLat, agentLng, order.deliveryLat!, order.deliveryLng!);
            etaMin = loc.etaMinutes(km);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SizedBox(
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(agentLat ?? 14.4644, agentLng ?? 75.9218),
                      initialZoom: 14,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.quickkart.customer',
                      ),
                      MarkerLayer(markers: [
                        if (agentLat != null && agentLng != null)
                          Marker(
                            point: LatLng(agentLat, agentLng),
                            child: const Icon(Icons.delivery_dining,
                                color: AppColors.primary, size: 36),
                          ),
                        if (order.deliveryLat != null && order.deliveryLng != null)
                          Marker(
                            point: LatLng(order.deliveryLat!, order.deliveryLng!),
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
                      leading: const Icon(Icons.schedule, color: AppColors.secondary),
                      title: Text('Arriving in about $etaMin min'),
                      subtitle: const Text('Agent is on the way'),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: StatusStepper(current: order.status),
              )),
              if (_agent != null)
                Card(child: ListTile(
                  leading: const Icon(Icons.person, color: AppColors.primary),
                  title: Text(_agent?['users']?['name'] ?? 'Delivery agent'),
                  subtitle: const Text('Tap to call'),
                  trailing: IconButton(
                    icon: const Icon(Icons.call, color: AppColors.secondary),
                    onPressed: () => _call(_agent?['users']?['phone'] ?? ''),
                  ),
                )),
              if (atDoor && _otp != null)
                Card(
                  color: AppColors.secondary.withOpacity(0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      const Text('Show this OTP to the delivery agent'),
                      const SizedBox(height: 8),
                      Text(_otp!,
                          style: const TextStyle(
                              fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 8)),
                    ]),
                  ),
                ),
              if (order.status == OrderStatus.placed)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton(
                    onPressed: _cancel,
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                    child: const Text('Cancel Order'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
