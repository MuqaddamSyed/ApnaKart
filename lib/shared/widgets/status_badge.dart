import 'package:flutter/material.dart';
import '../models/order.dart';
import '../../core/constants/app_colors.dart';

/// Coloured pill for an order status.
class StatusBadge extends StatelessWidget {
  final OrderStatus status;
  const StatusBadge({super.key, required this.status});

  Color get _color {
    switch (status) {
      case OrderStatus.delivered:
        return AppColors.secondary;
      case OrderStatus.cancelled:
        return AppColors.danger;
      case OrderStatus.on_the_way:
      case OrderStatus.picked_up:
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(status.label,
          style: TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
