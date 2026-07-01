import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/product.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/widgets/product_grid_card.dart';
import '../../../shared/widgets/cart_store.dart';
import '../../../shared/widgets/cart_bar.dart';
import '../../../shared/widgets/skeleton.dart';

/// Search by product name with simple price filter.
/// When [category] is set (from a Home category tile), it opens showing that
/// category's products; typing a query then switches to name search.
class SearchScreen extends ConsumerStatefulWidget {
  final String? category;
  const SearchScreen({super.key, this.category});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  List<Product> _results = [];
  bool _loading = false;
  double _maxPrice = 1000;

  @override
  void initState() {
    super.initState();
    if (widget.category != null) _loadCategory(widget.category!);
  }

  Future<void> _loadCategory(String category) async {
    setState(() => _loading = true);
    final res = await ref.read(productServiceProvider).getProductsByCategory(category);
    if (mounted) setState(() { _results = res; _loading = false; });
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      // Empty query: fall back to the category list if we opened from a tile.
      if (widget.category != null) return _loadCategory(widget.category!);
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    final res = await ref.read(productServiceProvider).searchProducts(q.trim());
    setState(() { _results = res; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final filtered = _results.where((p) => p.salePrice <= _maxPrice).toList();
    return Scaffold(
      bottomNavigationBar: const CartBar(),
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: widget.category != null
                ? 'Search in ${widget.category}'
                : 'Search products or shops',
            border: InputBorder.none,
          ),
          onSubmitted: _search,
          onChanged: (v) { if (v.length > 2) _search(v); },
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('Max Rs.'),
                Expanded(
                  child: Slider(
                    value: _maxPrice,
                    min: 50, max: 2000, divisions: 39,
                    label: _maxPrice.round().toString(),
                    activeColor: AppColors.primary,
                    onChanged: (v) => setState(() => _maxPrice = v),
                  ),
                ),
                Text(_maxPrice.round().toString()),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const SkeletonList()
                : filtered.isEmpty
                    ? Center(child: Text(widget.category != null
                        ? 'No products in ${widget.category} yet'
                        : 'Type to search products'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.62,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final p = filtered[i];
                          return ProductGridCard(
                            product: p,
                            quantity: cart.qtyOf(p.id),
                            onQuantityChanged: (q) =>
                                ref.read(cartProvider.notifier).setQuantity(p, q),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
