import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/product.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';

/// Product moderation: hide listings + flag price-cap violations.
class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});
  @override
  State<ModerationScreen> createState() => _State();
}

class _State extends State<ModerationScreen> {
  // Simple Phase-1 price cap: flag if sale_price > 5x MRP heuristic, etc.
  static const double priceCap = 5000;
  List<Product> _products = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final rows = await supabase.from('products').select().order('created_at', ascending: false);
    _products = (rows as List).map((e) => Product.fromMap(e)).toList();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _remove(Product p) async {
    await supabase.from('products').update({'is_available': false}).eq('id', p.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Product Moderation', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ..._products.map((p) {
          final overCap = p.salePrice > priceCap;
          return Card(
            child: ListTile(
              leading: Icon(Icons.inventory_2,
                  color: overCap ? AppColors.danger : AppColors.primary),
              title: Text(p.name),
              subtitle: Text('${formatRupees(p.salePrice)}'
                  '${overCap ? '  •  PRICE CAP EXCEEDED' : ''}'),
              trailing: TextButton(
                onPressed: () => _remove(p),
                child: const Text('Remove', style: TextStyle(color: AppColors.danger)),
              ),
            ),
          );
        }),
      ],
    );
  }
}
