import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/address_service.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/cart_store.dart';

/// Cart: edit quantities, pick address, COD only, place order.
class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});
  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _addressCtrl = TextEditingController();
  bool _placing = false;
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    _prefillAddress();
  }

  /// Pre-fill the delivery address + location with the customer's saved defaults
  /// so the order carries coordinates the delivery agent can navigate to.
  Future<void> _prefillAddress() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    final row = await supabase
        .from('customers')
        .select('default_address,default_lat,default_lng')
        .eq('id', uid)
        .maybeSingle();
    final addr = row?['default_address'] as String?;
    if (!mounted) return;
    setState(() {
      _lat = (row?['default_lat'] as num?)?.toDouble();
      _lng = (row?['default_lng'] as num?)?.toDouble();
      if (addr != null && addr.isNotEmpty && _addressCtrl.text.isEmpty) {
        _addressCtrl.text = addr;
      }
    });
  }

  Future<void> _placeOrder() async {
    final cart = ref.read(cartProvider);
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      // Login is required to place an order; send them to sign in.
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to place your order')));
      context.go(Routes.login);
      return;
    }
    if (cart.supplierId == null) return;
    if (_addressCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a delivery address')));
      return;
    }
    setState(() => _placing = true);
    try {
      // Best-effort: grab a fresh GPS fix at checkout; fall back to the saved
      // location from onboarding. Either way the agent gets coordinates.
      var lat = _lat;
      var lng = _lng;
      try {
        final loc = await ref.read(locationServiceProvider).getCurrentLocation();
        lat = loc.latitude;
        lng = loc.longitude;
      } catch (_) {/* keep saved location if GPS unavailable/denied */}
      final res = await ref.read(orderServiceProvider).placeOrder(
            customerId: uid,
            supplierId: cart.supplierId!,
            items: cart.items.values.toList(),
            address: _addressCtrl.text.trim(),
            lat: lat,
            lng: lng,
          );
      ref.read(cartProvider.notifier).clear();
      if (!mounted) return;
      context.go('${Routes.tracking}/${res.orderId}');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final subtotal = cart.subtotal;
    const fee = AppConstants.flatDeliveryFee;
    final total = subtotal + fee;

    if (cart.count == 0) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cart')),
        body: const Center(child: Text('Your cart is empty')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...cart.items.values.map((i) => Card(
                child: ListTile(
                  title: Text(i.productName),
                  subtitle: Text('${i.unit ?? ''}  ${formatRupees(i.unitPrice)}'),
                  trailing: Text('x${i.quantity}   ${formatRupees(i.totalPrice)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              )),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Delivery address',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.bookmark_border, size: 18),
              label: const Text('Saved addresses'),
              onPressed: () async {
                final picked = await context.push<bool>(
                    '${Routes.addresses}?select=1');
                await ref.read(currentAddressProvider.notifier).refresh();
                final a = ref.read(currentAddressProvider);
                if (picked == true && a != null) {
                  setState(() {
                    _addressCtrl.text = a.text;
                    _lat = a.lat;
                    _lng = a.lng;
                  });
                }
              },
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _addressCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'House, street, area, city, pincode',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row('Subtotal', formatRupees(subtotal)),
                  _row('Delivery fee', formatRupees(fee)),
                  const Divider(),
                  _row('Total', formatRupees(total), bold: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const ListTile(
            leading: Icon(Icons.payments_outlined, color: AppColors.secondary),
            title: Text('Cash on Delivery'),
            subtitle: Text('Pay when your order arrives'),
            trailing: Icon(Icons.check_circle, color: AppColors.secondary),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton(
            onPressed: _placing ? null : _placeOrder,
            child: _placing
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Place Order  •  ${formatRupees(total)}'),
          ),
        ),
      ),
    );
  }

  Widget _row(String l, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
            Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
          ],
        ),
      );
}
