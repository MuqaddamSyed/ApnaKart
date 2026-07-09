import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/models/product.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/product_card.dart';
import '../../../shared/widgets/cart_store.dart';
import '../../../shared/widgets/skeleton.dart';

/// Shop header + product list grouped by category + sticky cart bar.
class SupplierDetailScreen extends ConsumerStatefulWidget {
  final String supplierId;
  const SupplierDetailScreen({super.key, required this.supplierId});
  @override
  ConsumerState<SupplierDetailScreen> createState() => _State();
}

class _State extends ConsumerState<SupplierDetailScreen> {
  Map<String, dynamic>? _shop;
  List<Product> _products = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final shop = await supabase.from('suppliers').select().eq('id', widget.supplierId).maybeSingle();
      final products = await ref.read(productServiceProvider).getProductsBySupplier(widget.supplierId);
      _shop = shop;
      _products = products;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    if (_loading) return const Scaffold(body: SkeletonList());
    final isOpen = _shop?['is_open'] as bool? ?? true;
    final byCategory = <String, List<Product>>{};
    for (final p in _products) {
      byCategory.putIfAbsent(p.category ?? 'Other', () => []).add(p);
    }
    return Scaffold(
      appBar: AppBar(title: Text(_shop?['shop_name'] ?? 'Shop')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(radius: 28, backgroundColor: AppColors.background,
                      child: Icon(Icons.storefront, color: AppColors.primary)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_shop?['shop_name'] ?? '',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        Text(_shop?['address'] ?? '',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.star, size: 14, color: AppColors.warning),
                          Text(' ${_shop?['rating'] ?? 0}  '),
                          const Icon(Icons.timer_outlined, size: 14, color: AppColors.textMuted),
                          const Text(' 15-20 min'),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isOpen)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: const [
                Icon(Icons.storefront, color: AppColors.danger),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This shop is currently closed. You can browse, but ordering is unavailable until it reopens.',
                    style: TextStyle(
                        color: AppColors.danger, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 12),
          // When the shop is closed, don't show any products at all.
          if (isOpen)
            ...byCategory.entries.expand((e) => [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(e.key.replaceAll('_', ' ').toUpperCase(),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                  ...e.value.map((p) => ProductCard(
                        product: p,
                        quantity: cart.qtyOf(p.id),
                        onQuantityChanged: (q) =>
                            ref.read(cartProvider.notifier).setQuantity(p, q),
                      )),
                ]),
        ],
      ),
      bottomNavigationBar: cart.count == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ElevatedButton(
                  onPressed: () => context.push(Routes.cart),
                  child: Text('${cart.count} items  •  ${formatRupees(cart.subtotal)}   View Cart'),
                ),
              ),
            ),
    );
  }
}
