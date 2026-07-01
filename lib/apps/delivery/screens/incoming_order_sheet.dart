import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/models/order.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';

/// Incoming order popup with a 15-second accept/decline timer.
class IncomingOrderSheet extends ConsumerStatefulWidget {
  final Order order;
  const IncomingOrderSheet({super.key, required this.order});
  @override
  ConsumerState<IncomingOrderSheet> createState() => _State();
}

class _State extends ConsumerState<IncomingOrderSheet> {
  int _seconds = AppConstants.acceptWindowSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_seconds <= 1) { t.cancel(); if (mounted) Navigator.pop(context); }
      else { setState(() => _seconds--); }
    });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  Future<void> _accept() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    // Atomically claim it — the order stays "confirmed" (assigned) until the
    // agent actually picks it up. First agent to accept wins.
    final claimed = await ref.read(orderServiceProvider).claimOrder(widget.order.id, uid);
    if (!mounted) return;
    Navigator.pop(context);
    if (claimed) {
      context.push('${Routes.active}/${widget.order.id}');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Another partner already took this order')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('New Delivery Request',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            CircleAvatar(backgroundColor: AppColors.primary, radius: 16,
                child: Text('$_seconds', style: const TextStyle(color: Colors.white))),
          ]),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.store, color: AppColors.primary),
            title: const Text('Pickup from supplier'),
            subtitle: Text('Order #${o.id.substring(0, 8)}'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.location_on, color: AppColors.secondary),
            title: const Text('Drop to customer'),
            subtitle: Text(o.deliveryAddress ?? '-'),
          ),
          Text('Estimated earnings: ${formatRupees(o.deliveryFee == 0 ? 20 : o.deliveryFee)}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: ElevatedButton(onPressed: _accept, child: const Text('Accept'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () => Navigator.pop(context),
                child: const Text('Decline'))),
          ]),
        ],
      ),
    );
  }
}
