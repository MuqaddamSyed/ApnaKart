import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import '../models/order_item.dart';

/// In-memory cart scoped to a single supplier (Phase 1: one supplier/order).
class CartState {
  final String? supplierId;
  final Map<String, OrderItem> items; // productId -> line
  const CartState({this.supplierId, this.items = const {}});

  int qtyOf(String productId) => items[productId]?.quantity ?? 0;
  double get subtotal => items.values.fold(0, (s, i) => s + i.totalPrice);
  int get count => items.values.fold(0, (s, i) => s + i.quantity);

  CartState copyWith({String? supplierId, Map<String, OrderItem>? items}) =>
      CartState(supplierId: supplierId ?? this.supplierId, items: items ?? this.items);
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(const CartState());

  void setQuantity(Product p, int qty) {
    // Reset cart if switching suppliers.
    final base = (state.supplierId != null && state.supplierId != p.supplierId)
        ? const CartState()
        : state;
    final items = Map<String, OrderItem>.from(base.items);
    if (qty <= 0) {
      items.remove(p.id);
    } else {
      items[p.id] = OrderItem(
        productId: p.id,
        productName: p.name,
        quantity: qty,
        unitPrice: p.salePrice,
        imageUrl: p.imageUrl,
        unit: p.unit,
      );
    }
    state = CartState(
      supplierId: items.isEmpty ? null : p.supplierId,
      items: items,
    );
  }

  void clear() => state = const CartState();
}

final cartProvider =
    StateNotifierProvider<CartNotifier, CartState>((ref) => CartNotifier());
