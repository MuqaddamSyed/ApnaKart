import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/product.dart';
import '../utils/formatters.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';

/// Grid product card (image on top, price, discount, add control).
/// Used for category / search listings — a 2-column shopping grid.
class ProductGridCard extends StatelessWidget {
  final Product product;
  final int quantity;
  final ValueChanged<int> onQuantityChanged;

  const ProductGridCard({
    super.key,
    required this.product,
    required this.quantity,
    required this.onQuantityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final showDiscount = product.discountPercent >= AppConstants.discountBadgeMin;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: AspectRatio(
                  aspectRatio: 1.15,
                  child: product.imageUrl == null
                      ? Container(
                          color: AppColors.background,
                          child: const Icon(Icons.shopping_bag_outlined,
                              size: 36, color: AppColors.textMuted))
                      : CachedNetworkImage(
                          imageUrl: product.imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: AppColors.background),
                          errorWidget: (_, __, ___) => Container(
                              color: AppColors.background,
                              child: const Icon(Icons.image_not_supported_outlined,
                                  color: AppColors.textMuted)),
                        ),
                ),
              ),
              Positioned(right: 8, bottom: 8, child: _addControl()),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, height: 1.15)),
                if (product.unit != null) ...[
                  const SizedBox(height: 4),
                  Text(product.unit!,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
                const SizedBox(height: 6),
                if (showDiscount)
                  Text('${product.discountPercent}% OFF',
                      style: const TextStyle(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                Row(children: [
                  Text(formatRupees(product.salePrice),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (showDiscount) ...[
                    const SizedBox(width: 6),
                    Text(formatRupees(product.mrp),
                        style: const TextStyle(
                            decoration: TextDecoration.lineThrough,
                            fontSize: 12,
                            color: AppColors.textMuted)),
                  ],
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _addControl() {
    if (quantity == 0) {
      return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () { HapticFeedback.lightImpact(); onQuantityChanged(1); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary),
            ),
            child: const Text('ADD',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _btn(Icons.remove, () => onQuantityChanged(quantity - 1)),
        Text('$quantity',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        _btn(Icons.add, () => onQuantityChanged(quantity + 1)),
      ]),
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      );
}
