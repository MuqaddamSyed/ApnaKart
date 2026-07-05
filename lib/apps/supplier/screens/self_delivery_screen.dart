import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/order_item.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/utils/formatters.dart';

/// Supplier delivers a single-shop order themselves. No map/GPS — just the
/// customer's details, the items, and the OTP handoff to confirm delivery.
class SelfDeliveryScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const SelfDeliveryScreen({super.key, required this.sessionId});
  @override
  ConsumerState<SelfDeliveryScreen> createState() => _State();
}

class _State extends ConsumerState<SelfDeliveryScreen> {
  String? _customerName;
  String? _customerPhone;
  String? _customerAddress;
  List<OrderItem> _items = [];
  bool _arrived = false;
  bool _busy = false;
  String? _error;
  final _otpCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service = ref.read(orderServiceProvider);
    final contacts = await service.getSessionContacts(widget.sessionId);
    final orders = await service.getSessionOrders(widget.sessionId);
    final items = orders.isNotEmpty
        ? await service.getOrderItems(orders.first.id)
        : <OrderItem>[];
    if (mounted) {
      setState(() {
        _customerName = contacts.customerName;
        _customerPhone = contacts.customerPhone;
        _customerAddress = contacts.customerAddress;
        _items = items;
      });
    }
  }

  Future<void> _call(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _reached() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(orderServiceProvider).markSessionArrived(widget.sessionId);
      if (mounted) setState(() => _arrived = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not update: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deliver() async {
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
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not complete: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(orderServiceProvider).rejectSessionByAgent(widget.sessionId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not update: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deliver Order')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Customer contact.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.person, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_customerName ?? 'Customer',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                    if (_customerPhone != null)
                      IconButton(
                        icon: const Icon(Icons.call,
                            color: AppColors.secondary),
                        tooltip: 'Call customer',
                        onPressed: () => _call(_customerPhone),
                      ),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.location_on,
                        size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_customerAddress ?? 'Address not available',
                          style: const TextStyle(color: AppColors.textMuted)),
                    ),
                  ]),
                  if (_customerPhone != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 22),
                      child: Text(_customerPhone!,
                          style: const TextStyle(
                              color: AppColors.secondary,
                              fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Items.
          const Text('Items', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: _items
                    .map((it) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            Expanded(child: Text(it.productName)),
                            Text('× ${it.quantity}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: 10),
                            Text(formatRupees(it.unitPrice * it.quantity)),
                          ]),
                        ))
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Deliver flow.
          if (!_arrived)
            ElevatedButton.icon(
              icon: const Icon(Icons.location_on),
              label: const Text('Reached Customer'),
              onPressed: _busy ? null : _reached,
            )
          else ...[
            const Text('Ask the customer for their 4-digit code',
                style: TextStyle(fontWeight: FontWeight.w600)),
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
              onPressed: _busy ? null : _deliver,
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            icon: const Icon(Icons.cancel),
            label: const Text('Cannot deliver / Return'),
            onPressed: _busy ? null : _reject,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
