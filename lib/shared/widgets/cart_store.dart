import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import '../models/order_item.dart';

/// Multi-supplier cart: groups items by supplierId.
class CartState {
  /// supplierId -> { productId -> OrderItem }
  final Map<String, Map<String, OrderItem>> supplierItems;

  const CartState({this.supplierItems = const {}});

  int qtyOf(String productId) {
    for (final items in supplierItems.values) {
      if (items.containsKey(productId)) return items[productId]!.quantity;
    }
    return 0;
  }

  double get subtotal => supplierItems.values
      .fold(0, (s, m) => s + m.values.fold(0.0, (ss, i) => ss + i.totalPrice));

  int get count => supplierItems.values
      .fold(0, (s, m) => s + m.values.fold(0, (ss, i) => ss + i.quantity));

  bool get isEmpty => count == 0;

  /// All items as a flat list (for display).
  List<OrderItem> get allItems =>
      supplierItems.values.expand((m) => m.values).toList();

  /// Items grouped by supplier: supplierId -> list of items.
  Map<String, List<OrderItem>> get bySupplier =>
      supplierItems.map((sid, m) => MapEntry(sid, m.values.toList()));

  /// First (or only) supplier id, for single-supplier backward compat.
  String? get supplierId =>
      supplierItems.isEmpty ? null : supplierItems.keys.first;
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(const CartState());

  void setQuantity(Product p, int qty) {
    final all = Map<String, Map<String, OrderItem>>.from(
        state.supplierItems.map((k, v) => MapEntry(k, Map.from(v))));

    all.putIfAbsent(p.supplierId, () => {});
    if (qty <= 0) {
      all[p.supplierId]!.remove(p.id);
      if (all[p.supplierId]!.isEmpty) all.remove(p.supplierId);
    } else {
      all[p.supplierId]![p.id] = OrderItem(
        productId: p.id,
        productName: p.name,
        quantity: qty,
        unitPrice: p.salePrice,
        imageUrl: p.imageUrl,
        unit: p.unit,
        supplierId: p.supplierId,
      );
    }
    state = CartState(supplierItems: all);
  }

  void clear() => state = const CartState();
}

final cartProvider =
    StateNotifierProvider<CartNotifier, CartState>((ref) => CartNotifier());
