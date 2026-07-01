import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/order.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';

/// Two-step delivery: navigate to supplier -> picked up -> navigate to
/// customer -> collect cash -> enter OTP -> mark delivered.
/// Pushes agent GPS every 10s while active.
class ActiveDeliveryScreen extends ConsumerStatefulWidget {
  final String orderId;
  const ActiveDeliveryScreen({super.key, required this.orderId});
  @override
  ConsumerState<ActiveDeliveryScreen> createState() => _State();
}

class _State extends ConsumerState<ActiveDeliveryScreen> {
  final _otpCtrl = TextEditingController();
  Timer? _ping;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startPinging();
  }

  /// Push location every 10s (AppConstants.agentPingSeconds).
  void _startPinging() {
    _ping = Timer.periodic(Duration(seconds: AppConstants.agentPingSeconds), (_) async {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;
      try {
        final loc = await ref.read(locationServiceProvider).getCurrentLocation();
        await ref.read(locationServiceProvider).updateAgentLocation(uid, loc.latitude, loc.longitude);
      } catch (_) {/* ignore transient gps errors */}
    });
  }

  @override
  void dispose() { _ping?.cancel(); super.dispose(); }

  Future<void> _call(String? phone) async {
    if (phone == null) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  /// Hand off turn-by-turn navigation to the phone's installed maps app.
  /// Free — no Maps API key. Opens Google/Apple/OSM maps with directions.
  Future<void> _navigate(LatLng dest) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${dest.latitude},${dest.longitude}');
    if (await canLaunchUrl(uri)) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _markPickedUp() =>
      ref.read(orderServiceProvider).updateOrderStatus(widget.orderId, OrderStatus.on_the_way);

  Future<void> _markDelivered() async {
    // The verify-delivery-otp Edge Function verifies the hashed OTP and, on
    // match, atomically marks delivered + increments agent earnings server-side.
    final ok = await ref.read(orderServiceProvider)
        .confirmDelivery(widget.orderId, _otpCtrl.text.trim());
    if (!ok) { setState(() => _error = 'OTP does not match'); return; }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Active Delivery')),
      body: StreamBuilder<Order>(
        stream: ref.read(orderServiceProvider).listenToOrder(widget.orderId),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final o = snap.data!;
          final toCustomer = o.status == OrderStatus.on_the_way;
          final target = toCustomer
              ? LatLng(o.deliveryLat ?? 14.47, o.deliveryLng ?? 75.92)
              : const LatLng(14.4644, 75.9218); // supplier (demo)
          return Column(
            children: [
              SizedBox(
                height: 220,
                child: FlutterMap(
                  options: MapOptions(initialCenter: target, initialZoom: 14),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.quickkart.delivery',
                    ),
                    MarkerLayer(markers: [
                      Marker(point: target, child: Icon(
                          toCustomer ? Icons.home : Icons.store,
                          color: AppColors.primary, size: 36)),
                    ]),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(child: ListTile(
                      leading: Icon(toCustomer ? Icons.home : Icons.store, color: AppColors.primary),
                      title: Text(toCustomer ? 'Deliver to customer' : 'Pick up from supplier'),
                      subtitle: Text(toCustomer ? (o.deliveryAddress ?? '') : 'Supplier location'),
                      trailing: IconButton(
                        icon: const Icon(Icons.call, color: AppColors.secondary),
                        onPressed: () => _call(null),
                      ),
                    )),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.navigation),
                      label: Text(toCustomer ? 'Navigate to customer' : 'Navigate to supplier'),
                      onPressed: () => _navigate(target),
                    ),
                    const SizedBox(height: 8),
                    if (!toCustomer)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.check),
                        label: const Text('Picked Up'),
                        onPressed: _markPickedUp,
                      ),
                    if (toCustomer) ...[
                      Card(
                        color: AppColors.warning.withOpacity(0.1),
                        child: const ListTile(
                          leading: Icon(Icons.payments, color: AppColors.warning),
                          title: Text('Collect Cash (COD)'),
                          subtitle: Text('Collect order total from customer'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _otpCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Enter 4-digit OTP from customer',
                          errorText: _error,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
                        onPressed: _markDelivered,
                        child: const Text('Mark Delivered'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
