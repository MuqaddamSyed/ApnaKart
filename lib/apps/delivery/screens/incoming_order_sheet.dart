import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_session.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';

/// Incoming session popup with a 15-second accept/decline timer.
class IncomingOrderSheet extends ConsumerStatefulWidget {
  final OrderSession session;
  const IncomingOrderSheet({super.key, required this.session});
  @override
  ConsumerState<IncomingOrderSheet> createState() => _State();
}

class _State extends ConsumerState<IncomingOrderSheet> {
  int _seconds = AppConstants.acceptWindowSeconds;
  Timer? _timer;
  List<Order> _shops = [];
  Map<String, String> _supplierPhones = {};
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    _loadShops();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_seconds <= 1) {
        t.cancel();
        if (mounted) Navigator.of(context).pop();
      } else {
        setState(() => _seconds--);
      }
    });
  }

  Future<void> _loadShops() async {
    final service = ref.read(orderServiceProvider);
    final shops = await service.getSessionOrders(widget.session.id);
    final contacts = await service.getSessionContacts(widget.session.id);
    if (mounted) {
      setState(() {
        _shops = shops;
        _supplierPhones = contacts.supplierPhones;
      });
    }
  }

  Future<void> _call(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _decline() {
    _timer?.cancel();
    Navigator.of(context).pop();
  }

  Future<void> _accept() async {
    if (_accepting) return;
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    setState(() => _accepting = true);
    _timer?.cancel();
    try {
      final claimed = await ref
          .read(orderServiceProvider)
          .claimSession(widget.session.id, uid);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (claimed) {
        context.push('${Routes.active}/${widget.session.id}');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Another partner already took this order')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _accepting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not accept: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return SafeArea(
      top: false,
      // Extra bottom margin lifts the sheet (and the Accept/Decline buttons)
      // higher off the screen edge so they're easy to reach.
      minimum: const EdgeInsets.only(bottom: 28),
      child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('New Delivery Request',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            CircleAvatar(
              backgroundColor: AppColors.primary,
              radius: 16,
              child: Text('$_seconds',
                  style: const TextStyle(color: Colors.white)),
            ),
          ]),
          const SizedBox(height: 4),
          Text('Order #${s.shortId}',
              style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 12),

          // Shops to pick up from (name, shop, address).
          Text(
            _shops.isEmpty
                ? 'Pickup shops'
                : '${_shops.length} pickup ${_shops.length == 1 ? 'shop' : 'shops'}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          if (_shops.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Loading shop details…',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            )
          else
            ..._shops.map((o) {
              final phone = _supplierPhones[o.supplierId];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.store,
                      color: AppColors.primary, size: 28),
                  title: Text(o.supplierName ?? 'Supplier',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.supplierAddress ?? 'Address not set',
                          style: const TextStyle(
                              fontSize: 14, color: AppColors.textDark)),
                      if (phone != null)
                        Text(phone,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.secondary)),
                    ],
                  ),
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
            }),

          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.location_on,
                color: AppColors.secondary, size: 28),
            title: const Text('Drop to customer',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            subtitle: Text(s.deliveryAddress ?? '-',
                style: const TextStyle(
                    fontSize: 15, color: AppColors.textDark)),
          ),
          Text(
            'Estimated earnings: ${formatRupees(s.deliveryFee == 0 ? 20 : s.deliveryFee)}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _accepting ? null : _accept,
                  child: _accepting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Accept',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger),
                  onPressed: _accepting ? null : _decline,
                  child: const Text('Decline',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ]),
        ],
      ),
      ),
    );
  }
}
