import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_session.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';

/// Multi-supplier active delivery: navigate to each shop, pick up,
/// then deliver to customer. Shows supplier + customer contacts.
class ActiveDeliveryScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const ActiveDeliveryScreen({super.key, required this.sessionId});
  @override
  ConsumerState<ActiveDeliveryScreen> createState() => _State();
}

class _State extends ConsumerState<ActiveDeliveryScreen> {
  Timer? _ping;
  String? _error;
  bool _busy = false;
  bool _arrived = false;
  List<Order> _subOrders = [];
  String? _customerPhone;
  StreamSubscription<List<Order>>? _subOrdersSub;
  final _otpCtrl = TextEditingController();
  // supplierId -> phone
  Map<String, String> _supplierPhones = {};
  // supplierId -> picked up
  final Map<String, bool> _pickedUp = {};

  @override
  void initState() {
    super.initState();
    _startPinging();
    _loadDetails();
    // Live sub-order updates so pickup/arrival state stays in sync.
    _subOrdersSub = ref
        .read(orderServiceProvider)
        .listenToSessionOrders(widget.sessionId)
        .listen((orders) {
      if (!mounted || orders.isEmpty) return;
      // Keep the enriched _subOrders list (it carries supplier/customer joins
      // the realtime stream lacks); only sync status-derived state here.
      setState(() {
        _arrived = orders.any((o) => o.status == OrderStatus.arrived);
        for (final o in orders) {
          // Reflect server-side status into the local picked-up map.
          if (o.status == OrderStatus.on_the_way ||
              o.status == OrderStatus.arrived ||
              o.status == OrderStatus.delivered) {
            _pickedUp[o.supplierId] = true;
          } else {
            _pickedUp.putIfAbsent(o.supplierId, () => false);
          }
        }
      });
    });
  }

  Future<void> _loadDetails() async {
    // Initial snapshot carries the supplier/customer joins for display.
    final service = ref.read(orderServiceProvider);
    final orders = await service.getSessionOrders(widget.sessionId);
    // Contacts come from a privacy-checked RPC (the users-table RLS hides
    // phones from a normal join). Supplier phones + the customer phone.
    final contacts = await service.getSessionContacts(widget.sessionId);
    if (mounted) {
      setState(() {
        _subOrders = orders;
        _supplierPhones = contacts.supplierPhones;
        _customerPhone = contacts.customerPhone;
        _arrived = orders.any((o) => o.status == OrderStatus.arrived);
        for (final o in orders) {
          _pickedUp.putIfAbsent(o.supplierId, () => false);
        }
      });
    }
  }

  void _startPinging() {
    _ping = Timer.periodic(
        Duration(seconds: AppConstants.agentPingSeconds), (_) async {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;
      try {
        final loc =
            await ref.read(locationServiceProvider).getCurrentLocation();
        await ref
            .read(locationServiceProvider)
            .updateAgentLocation(uid, loc.latitude, loc.longitude);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _ping?.cancel();
    _subOrdersSub?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _navigate(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open maps')),
      );
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

  bool get _allPickedUp =>
      _pickedUp.isNotEmpty && _pickedUp.values.every((v) => v);

  Future<void> _markPickedUpFromSupplier(String supplierId, String orderId) async {
    setState(() => _pickedUp[supplierId] = true);
    await ref
        .read(orderServiceProvider)
        .updateOrderStatus(orderId, OrderStatus.on_the_way);
  }

  Future<void> _markArrived() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await ref
          .read(orderServiceProvider)
          .markSessionArrived(widget.sessionId);
      // Advance the UI immediately instead of waiting on the realtime stream
      // (which can lag and make the button look hung).
      if (mounted) setState(() => _arrived = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not update: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markAccepted() async {
    if (_busy) return;
    final otp = _otpCtrl.text.trim();
    if (otp.length != 4) {
      setState(() => _error = 'Enter the 4-digit code the customer shows you.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await ref
          .read(orderServiceProvider)
          .completeSessionDeliveryWithOtp(widget.sessionId, otp);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not complete: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markRejected() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(orderServiceProvider)
          .rejectSessionByCustomer(widget.sessionId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not update: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Active Delivery')),
      body: StreamBuilder<OrderSession>(
        stream: ref
            .read(orderServiceProvider)
            .listenToSession(widget.sessionId),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load delivery: ${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted)),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final session = snap.data!;
          final isArrived = _arrived;
          final destLat = session.deliveryLat ?? 14.47;
          final destLng = session.deliveryLng ?? 75.92;

          return Column(
            children: [
              SizedBox(
                height: 200,
                child: FlutterMap(
                  options: MapOptions(
                      initialCenter: LatLng(destLat, destLng), initialZoom: 14),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.quickkart.delivery',
                    ),
                    MarkerLayer(markers: [
                      Marker(
                        point: LatLng(destLat, destLng),
                        child: const Icon(Icons.home,
                            color: AppColors.primary, size: 36),
                      ),
                    ]),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Order info.
                    Text(
                      'Order #${session.shortId}  •  ${formatRupees(session.deliveryFee)} earnings',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 12),

                    // Supplier stops.
                    const Text('Pickup Stops',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    ..._subOrders.map((o) {
                      final picked = _pickedUp[o.supplierId] ?? false;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(
                                  picked
                                      ? Icons.check_circle
                                      : Icons.store,
                                  color: picked
                                      ? AppColors.secondary
                                      : AppColors.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    o.supplierName ?? 'Supplier',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                if (_supplierPhones[o.supplierId] != null)
                                  IconButton(
                                    icon: const Icon(Icons.call,
                                        color: AppColors.secondary, size: 20),
                                    tooltip: 'Call shop',
                                    onPressed: () =>
                                        _call(_supplierPhones[o.supplierId]),
                                  ),
                              ]),
                              if (o.supplierAddress != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 32),
                                  child: Text(o.supplierAddress!,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textMuted)),
                                ),
                              const SizedBox(height: 8),
                              Row(children: [
                                if (o.supplierLat != null && o.supplierLng != null)
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.navigation,
                                          size: 16),
                                      label: const Text('Navigate'),
                                      onPressed: () => _navigate(
                                          o.supplierLat!, o.supplierLng!),
                                    ),
                                  ),
                                if (!picked) ...[
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.check, size: 16),
                                      label: const Text('Picked Up'),
                                      onPressed: () =>
                                          _markPickedUpFromSupplier(
                                              o.supplierId, o.id),
                                    ),
                                  ),
                                ] else
                                  const Expanded(
                                    child: Chip(
                                      label: Text('Picked Up ✓'),
                                      backgroundColor: Color(0xFFE8F5E9),
                                    ),
                                  ),
                              ]),
                            ],
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 12),

                    // Delivery address + customer call.
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.home, color: AppColors.secondary),
                              const SizedBox(width: 8),
                              const Text('Deliver to customer',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                              const Spacer(),
                              // Customer phone unlocks once everything is
                              // picked up (so the agent can call on the way).
                              if (_allPickedUp && _customerPhone != null)
                                IconButton(
                                  icon: const Icon(Icons.call,
                                      color: AppColors.secondary, size: 20),
                                  tooltip: 'Call customer',
                                  onPressed: () => _call(_customerPhone),
                                ),
                            ]),
                            Padding(
                              padding: const EdgeInsets.only(left: 32),
                              child: Text(session.deliveryAddress ?? '',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted)),
                            ),
                            if (_allPickedUp && _customerPhone != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 32, top: 2),
                                child: Text('📞 $_customerPhone',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.secondary,
                                        fontWeight: FontWeight.w600)),
                              ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.navigation, size: 16),
                              label: const Text('Navigate to customer'),
                              onPressed: () => _navigate(destLat, destLng),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Once all shops are picked up, show "Reached Customer".
                    if (_allPickedUp && !isArrived)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.location_on),
                        label: const Text('Reached Customer Location'),
                        onPressed: _busy ? null : _markArrived,
                      ),

                    // At the door: accept / reject.
                    if (isArrived) ...[
                      Card(
                        color: AppColors.warning.withOpacity(0.1),
                        child: ListTile(
                          leading: const Icon(Icons.payments,
                              color: AppColors.warning),
                          title: const Text('Collect Cash (COD)'),
                          subtitle: Text(
                              'Collect ${formatRupees(session.total)} from the customer'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _otpCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        decoration: const InputDecoration(
                          labelText: 'Delivery code from customer',
                          counterText: '',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.secondary),
                        icon: const Icon(Icons.check_circle),
                        label: const Text('Confirm Delivery'),
                        onPressed: _busy ? null : _markAccepted,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger),
                        icon: const Icon(Icons.cancel),
                        label: const Text('Rejected by customer'),
                        onPressed: _busy ? null : _markRejected,
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: AppColors.danger, fontSize: 12)),
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
