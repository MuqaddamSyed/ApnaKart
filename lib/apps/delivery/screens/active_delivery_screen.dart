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
import '../../../shared/utils/formatters.dart';

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
  Timer? _ping;
  String? _error;
  double? _supLat, _supLng;
  String? _supName, _supAddress;

  @override
  void initState() {
    super.initState();
    _startPinging();
    _loadSupplier();
  }

  /// Real pickup location (the shop) for the "navigate to supplier" leg.
  Future<void> _loadSupplier() async {
    final row = await supabase
        .from('orders')
        .select('suppliers(shop_name, lat, lng, address)')
        .eq('id', widget.orderId)
        .maybeSingle();
    final s = row?['suppliers'] as Map<String, dynamic>?;
    if (s != null && mounted) {
      setState(() {
        _supName = s['shop_name'] as String?;
        _supLat = (s['lat'] as num?)?.toDouble();
        _supLng = (s['lng'] as num?)?.toDouble();
        _supAddress = s['address'] as String?;
      });
    }
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

  Future<void> _markArrived() =>
      ref.read(orderServiceProvider).markArrived(widget.orderId);

  /// Customer accepted → complete + credit earnings (no OTP).
  Future<void> _markAccepted() async {
    try {
      await ref.read(orderServiceProvider).completeDelivery(widget.orderId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = 'Could not complete: $e');
    }
  }

  /// Customer refused the order at the door.
  Future<void> _markRejected() async {
    await ref.read(orderServiceProvider).rejectByCustomer(widget.orderId);
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
          // 3 legs: confirmed → go to shop; on_the_way → go to customer;
          // arrived → at the customer's door.
          final toShop = o.status == OrderStatus.confirmed;
          final target = toShop
              ? LatLng(_supLat ?? 14.4644, _supLng ?? 75.9218) // real shop location
              : LatLng(o.deliveryLat ?? 14.47, o.deliveryLng ?? 75.92);
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
                          toShop ? Icons.store : Icons.home,
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
                      leading: Icon(toShop ? Icons.store : Icons.home, color: AppColors.primary),
                      title: Text(toShop ? 'Pick up from shop' : 'Deliver to customer'),
                      subtitle: Text(toShop
                          ? [_supName, _supAddress].where((e) => e != null && e.isNotEmpty).join(' · ')
                          : (o.deliveryAddress ?? '')),
                    )),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.navigation),
                      label: Text(toShop ? 'Navigate to shop' : 'Navigate to customer'),
                      onPressed: () => _navigate(target),
                    ),
                    const SizedBox(height: 12),
                    // Leg 1: at the shop → picked up.
                    if (o.status == OrderStatus.confirmed)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.check),
                        label: const Text('Picked Up'),
                        onPressed: _markPickedUp,
                      ),
                    // Leg 2: on the way → reached the customer.
                    if (o.status == OrderStatus.on_the_way)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.location_on),
                        label: const Text('Reached Customer Location'),
                        onPressed: _markArrived,
                      ),
                    // Leg 3: at the door → collect COD, then accept or reject.
                    if (o.status == OrderStatus.arrived) ...[
                      Card(
                        color: AppColors.warning.withOpacity(0.1),
                        child: ListTile(
                          leading: const Icon(Icons.payments, color: AppColors.warning),
                          title: const Text('Collect Cash (COD)'),
                          subtitle: Text('Collect ${formatRupees(o.total)} from the customer'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
                        icon: const Icon(Icons.check_circle),
                        label: const Text('Delivered — customer accepted'),
                        onPressed: _markAccepted,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                        icon: const Icon(Icons.cancel),
                        label: const Text('Rejected by customer'),
                        onPressed: _markRejected,
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_error!,
                              style: const TextStyle(color: AppColors.danger, fontSize: 12)),
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
