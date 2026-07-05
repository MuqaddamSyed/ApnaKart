import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/product.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/widgets/cart_store.dart';
import '../../../shared/widgets/cart_bar.dart';
import '../../../shared/widgets/product_card.dart';
import '../../../shared/widgets/skeleton.dart';

/// Fast Food: orderable items in the 'Fast Food' category, grouped by the
/// shop that sells them. Uses the same cart/order flow as everything else.
class FastFoodScreen extends ConsumerStatefulWidget {
  const FastFoodScreen({super.key});
  @override
  ConsumerState<FastFoodScreen> createState() => _State();
}

class _State extends ConsumerState<FastFoodScreen> {
  bool _loading = true;
  Map<String, List<Product>> _byShop = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await supabase
        .from('products')
        .select('*, suppliers(shop_name, is_open)')
        .eq('category', 'Fast Food')
        .eq('is_available', true);
    final map = <String, List<Product>>{};
    for (final r in (rows as List)) {
      final shop = (r['suppliers']?['shop_name'] as String?) ?? 'Fast Food';
      map.putIfAbsent(shop, () => []).add(Product.fromMap(r));
    }
    if (mounted) setState(() { _byShop = map; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Fast Food')),
      bottomNavigationBar: const CartBar(),
      body: _loading
          ? const SkeletonList()
          : _byShop.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fastfood_outlined, size: 44, color: AppColors.textMuted),
                        SizedBox(height: 8),
                        Text('No fast food items available yet',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: _byShop.entries.expand((e) => [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(children: [
                              const Icon(Icons.storefront, size: 18, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Text(e.key,
                                  style: const TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                          ...e.value.map((p) => ProductCard(
                                product: p,
                                quantity: cart.qtyOf(p.id),
                                onQuantityChanged: (q) =>
                                    ref.read(cartProvider.notifier).setQuantity(p, q),
                              )),
                        ]).toList(),
                  ),
                ),
    );
  }
}
