import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/product.dart';
import '../utils/formatters.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';

/// Product card with image, MRP strikethrough, sale price, discount badge,
/// and a +/- quantity control. Used in supplier-detail and search.
class ProductCard extends StatelessWidget {
  final Product product;
  final int quantity;
  final ValueChanged<int> onQuantityChanged;

  const ProductCard({
    super.key,
    required this.product,
    required this.quantity,
    required this.onQuantityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final showDiscount = product.discountPercent >= AppConstants.discountBadgeMin;
    final card = Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 64,
                height: 64,
                child: product.imageUrl == null
                    ? Container(
                        color: AppColors.background,
                        child: const Icon(Icons.shopping_bag_outlined,
                            color: AppColors.textMuted),
                      )
                    : CachedNetworkImage(
                        imageUrl: product.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: AppColors.background),
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.image_not_supported_outlined),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (product.unit != null)
                    Text(product.unit!,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(formatRupees(product.salePrice),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark)),
                      const SizedBox(width: 6),
                      if (showDiscount)
                        Text(formatRupees(product.mrp),
                            style: const TextStyle(
                              decoration: TextDecoration.lineThrough,
                              fontSize: 12,
                              color: AppColors.textMuted,
                            )),
                    ],
                  ),
                ],
              ),
            ),
            if (showDiscount)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${product.discountPercent}% OFF',
                    style: const TextStyle(color: Colors.white, fontSize: 10)),
              ),
            if (product.supplierIsOpen)
              _QtyControl(quantity: quantity, onChanged: onQuantityChanged)
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Closed',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
    if (product.supplierIsOpen) return card;
    // Shop closed → show the whole card in black & white and non-orderable.
    return Opacity(
      opacity: 0.85,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: card,
      ),
    );
  }
}

class _QtyControl extends StatelessWidget {
  final int quantity;
  final ValueChanged<int> onChanged;
  const _QtyControl({required this.quantity, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (quantity == 0) {
      return SizedBox(
        height: 36,
        child: OutlinedButton(
          onPressed: () { HapticFeedback.lightImpact(); onChanged(1); },
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: const Text('ADD'),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _btn(Icons.remove, () => onChanged(quantity - 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('$quantity',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          _btn(Icons.add, () => onChanged(quantity + 1)),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      );
}
