import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/models/product.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/skeleton.dart';

/// Product list with availability toggle + FAB to add.
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});
  @override
  ConsumerState<ProductsScreen> createState() => _State();
}

class _State extends ConsumerState<ProductsScreen> {
  List<Product> _products = [];
  bool _approved = false;
  bool _hasShopProfile = false;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid != null) {
        final shop = await supabase
            .from('suppliers')
            .select('is_verified')
            .eq('id', uid)
            .maybeSingle();
        _hasShopProfile = shop != null;
        _approved = shop?['is_verified'] as bool? ?? false;
        _products = _approved
            ? await ref.read(productServiceProvider).getProductsBySupplier(uid)
            : [];
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(Product p, bool v) async {
    await ref.read(productServiceProvider).updateProduct(p.id, {'is_available': v});
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      floatingActionButton: _approved
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add),
              label: const Text('Add Product'),
              onPressed: () async {
                await context.push(Routes.editProduct);
                _load();
              },
            )
          : null,
      body: _loading
          ? const SkeletonList()
          : !_hasShopProfile
              ? const _ApprovalMessage(
                  title: 'Set up your shop first',
                  message: 'Create your shop profile from the Dashboard tab before adding products.',
                )
          : !_approved
              ? const _ApprovalMessage(
                  title: 'Waiting for admin approval',
                  message: 'You can add products after your shop is verified.',
                )
          : _products.isEmpty
              ? const Center(child: Text('No products yet. Tap Add Product.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: _products.map((p) => Card(
                        child: ListTile(
                          title: Text(p.name),
                          subtitle: Text('${p.unit ?? ''}  ${formatRupees(p.salePrice)}  •  stock ${p.stockQty}'),
                          trailing: Switch(
                            value: p.isAvailable,
                            activeColor: AppColors.secondary,
                            onChanged: (v) => _toggle(p, v),
                          ),
                          onTap: () async {
                            await context.push('${Routes.editProduct}?id=${p.id}');
                            _load();
                          },
                        ),
                      )).toList(),
                ),
    );
  }
}

class _ApprovalMessage extends StatelessWidget {
  final String title;
  final String message;
  const _ApprovalMessage({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_top, color: AppColors.warning, size: 44),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
