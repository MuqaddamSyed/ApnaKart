import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_item.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/notification_service.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';

/// Supplier packing screen: tick/cross per item, qty adjustment, Done.
class PackingScreen extends ConsumerStatefulWidget {
  final String orderId;
  const PackingScreen({super.key, required this.orderId});
  @override
  ConsumerState<PackingScreen> createState() => _State();
}

class _State extends ConsumerState<PackingScreen> {
  List<OrderItem> _items = [];
  bool _loading = true;
  bool _saving = false;
  String? _customerId;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items =
        await ref.read(orderServiceProvider).getOrderItems(widget.orderId);
    // Load customer id for notification.
    final row = await supabase
        .from('orders')
        .select('customer_id')
        .eq('id', widget.orderId)
        .maybeSingle();
    if (mounted) {
      setState(() {
        _items = items
            .map((i) => i.copyWith(
                isAvailable: i.isAvailable ?? true,
                availableQty: i.availableQty ?? i.quantity))
            .toList();
        _customerId = row?['customer_id'] as String?;
        _loading = false;
      });
    }
  }

  void _toggleAvailable(int idx, bool v) {
    setState(() {
      _items[idx] = _items[idx].copyWith(
        isAvailable: v,
        availableQty: v ? _items[idx].quantity : 0,
      );
    });
  }

  void _changeQty(int idx, int delta) {
    final item = _items[idx];
    final newQty = (item.availableQty ?? item.quantity) + delta;
    if (newQty < 0 || newQty > item.quantity) return;
    setState(() {
      _items[idx] = item.copyWith(
        availableQty: newQty,
        isAvailable: newQty > 0,
      );
    });
  }

  double get _revisedTotal => _items.fold(
      0, (s, i) => s + ((i.isAvailable ?? true) ? i.effectiveTotal : 0));

  Future<void> _donePacking() async {
    setState(() => _saving = true);
    try {
      for (final item in _items) {
        if (item.id == null) continue;
        await ref.read(orderServiceProvider).updateItemAvailability(
              item.id!,
              item.isAvailable ?? true,
              item.availableQty,
            );
      }

      // Move order to preparing.
      await ref
          .read(orderServiceProvider)
          .updateOrderStatus(widget.orderId, OrderStatus.preparing);

      // Notify customer of revised total.
      if (_customerId != null) {
        final allAvail = _items.every((i) => (i.isAvailable ?? true));
        final msg = allAvail
            ? 'Your order is being packed. All items available!'
            : 'Some items are unavailable. Revised total: ${formatRupees(_revisedTotal)}. Delivery partner will collect accordingly.';
        await NotificationService().sendPushToUser(
          _customerId!,
          'Order being packed',
          msg,
          type: 'order_update',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Packing saved!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Packing')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final item = _items[idx];
                      final avail = item.isAvailable ?? true;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            // Availability toggle.
                            GestureDetector(
                              onTap: () => _toggleAvailable(idx, !avail),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: avail
                                      ? AppColors.secondary
                                      : AppColors.danger,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  avail ? Icons.check : Icons.close,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.productName,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: avail
                                              ? null
                                              : AppColors.textMuted,
                                          decoration: avail
                                              ? null
                                              : TextDecoration.lineThrough)),
                                  Text(
                                    '${item.unit ?? ''} · ${formatRupees(item.unitPrice)}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            // Qty adjuster (only when available).
                            if (avail) ...[
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline,
                                    size: 20),
                                onPressed: () => _changeQty(idx, -1),
                              ),
                              Text(
                                '${item.availableQty ?? item.quantity}/${item.quantity}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline,
                                    size: 20),
                                onPressed: () => _changeQty(idx, 1),
                              ),
                            ] else
                              const Padding(
                                padding: EdgeInsets.only(right: 16),
                                child: Text('N/A',
                                    style: TextStyle(
                                        color: AppColors.danger,
                                        fontWeight: FontWeight.w600)),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // Summary + Done button.
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(blurRadius: 8, color: Colors.black.withOpacity(0.08))],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Revised total',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          Text(formatRupees(_revisedTotal),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: AppColors.primary)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.done_all),
                          label: _saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Done Packing'),
                          onPressed: _saving ? null : _donePacking,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
