import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/order.dart';

/// ============================================================
/// Admin design system — tokens + shared building blocks.
/// Component constructors are kept backward-compatible so every
/// admin screen picks up the new look for free.
/// ============================================================
class AdminTheme {
  // Surfaces
  static const bg = Color(0xFFF4F6FA); // content background
  static const card = Colors.white;
  static const border = Color(0xFFEAECF1);

  // Sidebar (dark, premium)
  static const sidebar = Color(0xFF0F172A); // slate-900
  static const sidebarPanel = Color(0xFF1E293B); // slate-800 (active/hover)
  static const sidebarText = Color(0xFF94A3B8); // slate-400
  static const sidebarActive = Colors.white;

  // Ink
  static const ink = Color(0xFF0F172A);
  static const inkMuted = Color(0xFF64748B);

  // Accent (brand)
  static const accent = AppColors.primary;

  // Chart palette (validated: CVD-safe, labels present).
  static const chartBlue = Color(0xFF2A78D6);
  static const cDelivered = Color(0xFF008300);
  static const cOutForDelivery = Color(0xFF2A78D6);
  static const cConfirmed = Color(0xFFEDA100);
  static const cWaiting = Color(0xFFEB6834);
  static const cCancelled = Color(0xFFE34948);

  static const radius = 16.0;
  static List<BoxShadow> get shadow => [
        BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 6)),
      ];
}

/// White rounded card container used across admin pages.
class AdminCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const AdminCard(
      {super.key, required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AdminTheme.card,
          borderRadius: BorderRadius.circular(AdminTheme.radius),
          border: Border.all(color: AdminTheme.border),
          boxShadow: AdminTheme.shadow,
        ),
        child: child,
      );
}

/// Card with a header row (title + optional trailing action) and a body.
class SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;
  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) => AdminCard(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AdminTheme.ink)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!,
                            style: const TextStyle(
                                fontSize: 12.5, color: AdminTheme.inkMuted)),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 16),
            child,
          ],
        ),
      );
}

/// KPI stat card: coloured icon chip, big value, label, optional pill.
class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 240,
        child: AdminCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const Spacer(),
                  if (subtitle != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(subtitle!,
                          style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AdminTheme.ink,
                      height: 1.1)),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      color: AdminTheme.inkMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );
}

/// Page title (with optional subtitle + trailing action).
class AdminPageTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const AdminPageTitle(this.title, {super.key, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AdminTheme.ink)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(subtitle!,
                          style: const TextStyle(
                              fontSize: 13.5, color: AdminTheme.inkMuted)),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// Coloured status pill for order/verification states.
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const StatusChip(this.label, this.color, {super.key});

  factory StatusChip.order(OrderStatus s) {
    final c = switch (s) {
      OrderStatus.delivered => AdminTheme.cDelivered,
      OrderStatus.cancelled || OrderStatus.returned => AdminTheme.cCancelled,
      OrderStatus.on_the_way || OrderStatus.picked_up || OrderStatus.arrived =>
        AdminTheme.chartBlue,
      _ => AdminTheme.cConfirmed,
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
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// A soft rounded icon button for toolbars.
class AdminIconButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback onPressed;
  const AdminIconButton(
      {super.key, required this.icon, this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) => Material(
        color: AdminTheme.bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Tooltip(
            message: tooltip ?? '',
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Icon(icon, size: 20, color: AdminTheme.inkMuted),
            ),
          ),
        ),
      );
}
