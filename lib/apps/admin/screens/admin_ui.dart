import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/order.dart';

/// Shared building blocks for a consistent, modern admin look.

/// Coloured status pill for order/verification states.
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const StatusChip(this.label, this.color, {super.key});

  factory StatusChip.order(OrderStatus s) {
    final c = switch (s) {
      OrderStatus.delivered => AppColors.secondary,
      OrderStatus.cancelled => AppColors.danger,
      OrderStatus.on_the_way || OrderStatus.picked_up => AppColors.primary,
      _ => AppColors.warning,
    };
    return StatusChip(s.label, c);
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

/// White rounded card container used across admin pages.
class AdminCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const AdminCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );
}

/// KPI stat card with a coloured icon chip.
class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 230,
        child: AdminCard(
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    Text(label,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// Page title used at the top of each admin content area.
class AdminPageTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const AdminPageTitle(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(
          children: [
            Text(title,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
      );
}
