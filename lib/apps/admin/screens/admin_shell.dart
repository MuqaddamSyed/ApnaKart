import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/services/providers.dart';
import 'login_screen.dart';
import 'overview_screen.dart';
import 'orders_screen.dart';
import 'suppliers_screen.dart';
import 'catalog_screen.dart';
import 'skus_screen.dart';
import 'agents_screen.dart';
import 'customers_screen.dart';
import 'moderation_screen.dart';
import 'analytics_screen.dart';

/// Modern admin dashboard shell: branded sidebar + top bar + content area.
class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});
  @override
  ConsumerState<AdminShell> createState() => _State();
}

class _State extends ConsumerState<AdminShell> {
  int _i = 0;

  static const _items = [
    (Icons.dashboard_outlined, 'Overview'),
    (Icons.receipt_long_outlined, 'Orders'),
    (Icons.storefront_outlined, 'Suppliers'),
    (Icons.inventory_2_outlined, 'Catalog'),
    (Icons.category_outlined, 'SKUs'),
    (Icons.delivery_dining_outlined, 'Agents'),
    (Icons.people_outline, 'Customers'),
    (Icons.flag_outlined, 'Moderation'),
    (Icons.bar_chart_outlined, 'Analytics'),
  ];

  static const _pages = [
    OverviewScreen(),
    AdminOrdersScreen(),
    AdminSuppliersScreen(),
    AdminCatalogScreen(),
    AdminSkusScreen(),
    AdminAgentsScreen(),
    AdminCustomersScreen(),
    ModerationScreen(),
    AnalyticsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 900;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      drawer: narrow ? Drawer(child: _sidebar(context)) : null,
      body: Row(
        children: [
          if (!narrow)
            SizedBox(width: 248, child: _sidebar(context)),
          Expanded(
            child: Column(
              children: [
                _topBar(context, narrow),
                Expanded(child: _pages[_i]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context, bool narrow) => Container(
        height: 64,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            if (narrow)
              Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
            Text(_items[_i].$2,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const Spacer(),
            const CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.person, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
            const Text('Administrator',
                style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w500)),
          ],
        ),
      );

  Widget _sidebar(BuildContext context) => Container(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delivery_dining, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppConstants.appName,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                      const Text('Admin Panel',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (var idx = 0; idx < _items.length; idx++)
                    _navItem(context, idx),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _tile(
                icon: Icons.logout,
                label: 'Logout',
                color: AppColors.danger,
                onTap: () async {
                  await ref.read(authServiceProvider).signOut();
                  if (context.mounted) {
                    Navigator.pushReplacement(context,
                        MaterialPageRoute(builder: (_) => const AdminLoginScreen()));
                  }
                },
              ),
            ),
          ],
        ),
      );

  Widget _navItem(BuildContext context, int idx) {
    final active = _i == idx;
    return _tile(
      icon: _items[idx].$1,
      label: _items[idx].$2,
      color: active ? AppColors.primary : AppColors.textMuted,
      bg: active ? AppColors.primary.withOpacity(0.1) : null,
      bold: active,
      onTap: () {
        setState(() => _i = idx);
        if (Scaffold.of(context).hasDrawer && Scaffold.of(context).isDrawerOpen) {
          Navigator.pop(context);
        }
      },
    );
  }

  Widget _tile({
    required IconData icon,
    required String label,
    required Color color,
    Color? bg,
    bool bold = false,
    required VoidCallback onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: bg ?? Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 12),
                  Text(label,
                      style: TextStyle(
                          color: color,
                          fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
                ],
              ),
            ),
          ),
        ),
      );
}
