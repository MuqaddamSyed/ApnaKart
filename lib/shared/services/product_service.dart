import 'dart:io';
import '../models/product.dart';
import '../../core/constants/supabase_config.dart';
import 'supabase_client.dart';

/// CRUD + search + image upload for products.
class ProductService {
  Future<List<Product>> getProductsBySupplier(String supplierId) async {
    final rows = await supabase
        .from('products')
        .select('*, suppliers(is_open)')
        .eq('supplier_id', supplierId)
        .order('created_at');
    return (rows as List).map((e) => Product.fromMap(e)).toList();
  }

  /// Search by product name. Optionally constrain to nearby suppliers first
  /// (caller passes resolved supplier ids) — kept simple here with ilike.
  Future<List<Product>> searchProducts(String query) async {
    final rows = await supabase
        .from('products')
        .select('*, suppliers(is_open)')
        .ilike('name', '%$query%')
        .eq('is_available', true)
        .limit(50);
    return (rows as List).map((e) => Product.fromMap(e)).toList();
  }

  /// Available products in a category — used by the Home category tiles.
  Future<List<Product>> getProductsByCategory(String category) async {
    final rows = await supabase
        .from('products')
        .select('*, suppliers(is_open)')
        .eq('category', category)
        .eq('is_available', true)
        .limit(100);
    return (rows as List).map((e) => Product.fromMap(e)).toList();
  }

  /// Products with discount over [minDiscount] — used for "Top Deals".
  Future<List<Product>> topDeals({int minDiscount = 20}) async {
    final rows = await supabase
        .from('products')
        .select('*, suppliers(is_open)')
        .gte('discount_percent', minDiscount)
        .eq('is_available', true)
        .limit(20);
    return (rows as List).map((e) => Product.fromMap(e)).toList();
  }

  Future<Product> addProduct(Product p) async {
    final row = await supabase.from('products').insert(p.toMap()).select().single();
    return Product.fromMap(row);
  }

  Future<void> updateProduct(String productId, Map<String, dynamic> updates) async {
    await supabase.from('products').update(updates).eq('id', productId);
  }

  /// Uploads to the public `product-images` bucket, returns a public URL.
  Future<String> uploadProductImage(File file, String fileName) async {
    final path = 'public/$fileName';
    await supabase.storage
        .from(SupabaseConfig.productImageBucket)
        .upload(path, file);
    return supabase.storage.from(SupabaseConfig.productImageBucket).getPublicUrl(path);
  }
}
