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
import 'package:cached_network_image/cached_network_image.dart';

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
  // supplierId -> shop name, so the cart shows real names not id codes.
  Map<String, String> _shopNames = {};

  @override
  void initState() {
    super.initState();
    _prefillAddress();
    _loadShopNames();
  }

  Future<void> _loadShopNames() async {
    final ids = ref.read(cartProvider).supplierItems.keys.toList();
    if (ids.isEmpty) return;
    final rows =
        await supabase.from('suppliers').select('id, shop_name').inFilter('id', ids);
    if (!mounted) return;
    setState(() {
      _shopNames = {
        for (final r in (rows as List))
          r['id'] as String: (r['shop_name'] as String?) ?? 'Shop'
      };
    });
  }

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
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to place your order')));
      context.go(Routes.login);
      return;
    }
    if (cart.isEmpty) return;
    if (_addressCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a delivery address')));
      return;
    }
    setState(() => _placing = true);
    try {
      var lat = _lat;
      var lng = _lng;
      // Only fall back to device GPS when no address coordinates were selected.
      // Otherwise the order could be delivered to the wrong (device) location
      // instead of the address the customer picked.
      if (lat == null || lng == null) {
        try {
          final loc = await ref.read(locationServiceProvider).getCurrentLocation();
          lat = loc.latitude;
          lng = loc.longitude;
        } catch (_) {}
      }

      final sessionId = await ref.read(orderServiceProvider).placeMultiSupplierOrder(
            customerId: uid,
            deliveryAddress: _addressCtrl.text.trim(),
            lat: lat,
            lng: lng,
            supplierItems: cart.bySupplier,
          );
      ref.read(cartProvider.notifier).clear();
      if (!mounted) return;
      // Use push (not go) so the customer can press back to return home.
      context.push('${Routes.tracking}/$sessionId');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  Widget _cartBtn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final subtotal = cart.subtotal;
    const fee = AppConstants.flatDeliveryFee;
    final total = subtotal + fee;

    if (cart.isEmpty) {
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
          // Items grouped by supplier.
          ...cart.bySupplier.entries.expand((entry) {
            final supplierId = entry.key;
            final items = entry.value;
            final shopSubtotal =
                items.fold<double>(0, (s, i) => s + i.totalPrice);
            return [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Row(children: [
                  const Icon(Icons.storefront, size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _shopNames[supplierId] ?? 'Shop',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                  Text(formatRupees(shopSubtotal),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted)),
                ]),
              ),
              ...items.map((i) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(children: [
                        // Thumbnail.
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: i.imageUrl == null
                                ? Container(
                                    color: AppColors.background,
                                    child: const Icon(
                                        Icons.shopping_bag_outlined,
                                        color: AppColors.textMuted, size: 20))
                                : CachedNetworkImage(
                                    imageUrl: i.imageUrl!,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) =>
                                        Container(color: AppColors.background),
                                    errorWidget: (_, __, ___) => Container(
                                        color: AppColors.background,
                                        child: const Icon(
                                            Icons.image_not_supported_outlined,
                                            size: 18)),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Name + price.
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(i.productName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              Text(
                                  '${i.unit ?? ''}  ${formatRupees(i.unitPrice)}  =  ${formatRupees(i.totalPrice)}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        // Quantity control.
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            _cartBtn(Icons.remove, () => ref
                                .read(cartProvider.notifier)
                                .setItemQuantity(i, i.quantity - 1)),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Text('${i.quantity}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                            ),
                            _cartBtn(Icons.add, () => ref
                                .read(cartProvider.notifier)
                                .setItemQuantity(i, i.quantity + 1)),
                          ]),
                        ),
                        // Remove.
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: AppColors.danger, size: 20),
                          tooltip: 'Remove',
                          onPressed: () => ref
                              .read(cartProvider.notifier)
                              .setItemQuantity(i, 0),
                        ),
                      ]),
                    ),
                  )),
            ];
          }),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Delivery address',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.bookmark_border, size: 18),
              label: const Text('Saved addresses'),
              onPressed: () async {
                final picked =
                    await context.push<bool>('${Routes.addresses}?select=1');
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (subtotal < AppConstants.minOrderValue)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Minimum order is ${formatRupees(AppConstants.minOrderValue)}. Add ${formatRupees(AppConstants.minOrderValue - subtotal)} more to check out.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ElevatedButton(
                onPressed: (_placing || subtotal < AppConstants.minOrderValue)
                    ? null
                    : _placeOrder,
                child: _placing
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text('Place Order  •  ${formatRupees(total)}'),
              ),
            ],
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
            Text(l,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
            Text(v,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
          ],
        ),
      );
}
