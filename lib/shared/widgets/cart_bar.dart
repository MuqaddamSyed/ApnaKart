import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routing/app_router.dart';
import '../utils/formatters.dart';
import 'cart_store.dart';

/// Persistent bottom bar shown whenever the cart has items. Tapping opens
/// the cart. Collapses to nothing when the cart is empty.
class CartBar extends ConsumerWidget {
  const CartBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    if (cart.count == 0) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(12),
        elevation: 6,
        shadowColor: AppColors.primary.withOpacity(0.4),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push(Routes.cart),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.shopping_cart, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  '${cart.count} item${cart.count > 1 ? 's' : ''}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Text(
                  formatRupees(cart.subtotal),
                  style: const TextStyle(color: Colors.white70),
                ),
                const Spacer(),
                const Text('View Cart',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
