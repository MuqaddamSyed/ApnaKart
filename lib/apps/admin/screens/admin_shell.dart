import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/services/providers.dart';
import 'admin_ui.dart';
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

/// Premium admin shell: dark grouped sidebar + top bar + content area.
class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});
  @override
  ConsumerState<AdminShell> createState() => _State();
}

class _State extends ConsumerState<AdminShell> {
  int _i = 0;
  int _reload = 0; // bump to remount the current page (global refresh)

  // (title, subtitle) per page index.
  static const _meta = <(String, String)>[
    ('Overview', 'Everything happening across myMinto today'),
    ('Orders', 'Every customer order, grouped by session'),
    ('Suppliers', 'Onboard, verify and manage shops'),
    ('Products', 'Per-supplier product catalog'),
    ('SKU Catalog', 'Master library of common products'),
    ('Delivery Agents', 'Verify agents and see who is online'),
    ('Customers', 'Registered customers'),
    ('Moderation', 'Review flagged products'),
    ('Analytics', 'Revenue, peak hours and supplier performance'),
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

  // Grouped navigation: (section label, [(icon, label, pageIndex)]).
  static const _sections = <(String, List<(IconData, String, int)>)>[
    ('', [(Icons.dashboard_rounded, 'Overview', 0)]),
    ('OPERATIONS', [
      (Icons.receipt_long_rounded, 'Orders', 1),
      (Icons.delivery_dining_rounded, 'Delivery Agents', 5),
    ]),
    ('CATALOG', [
      (Icons.storefront_rounded, 'Suppliers', 2),
      (Icons.inventory_2_rounded, 'Products', 3),
      (Icons.category_rounded, 'SKU Catalog', 4),
    ]),
    ('PEOPLE', [
      (Icons.people_alt_rounded, 'Customers', 6),
    ]),
    ('INSIGHTS', [
      (Icons.insights_rounded, 'Analytics', 8),
      (Icons.flag_rounded, 'Moderation', 7),
    ]),
  ];

  Future<void> _logout() async {
    await ref.read(authServiceProvider).signOut();
    if (mounted) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const AdminLoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 960;
    return Scaffold(
      backgroundColor: AdminTheme.bg,
      drawer: narrow ? Drawer(child: _sidebar()) : null,
      body: Row(
        children: [
          if (!narrow) SizedBox(width: 256, child: _sidebar()),
          Expanded(
            child: Column(
              children: [
                _topBar(narrow),
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey('$_i-$_reload'),
                    child: _pages[_i],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Top bar ----------------
  Widget _topBar(bool narrow) => Container(
        height: 72,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: AdminTheme.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            if (narrow)
              Builder(
                builder: (ctx) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AdminIconButton(
                      icon: Icons.menu_rounded,
                      onPressed: () => Scaffold.of(ctx).openDrawer()),
                ),
              ),
            // Slim breadcrumb (the big title lives in each page's header).
            Expanded(
              child: Row(children: [
                const Icon(Icons.grid_view_rounded,
                    size: 15, color: AdminTheme.inkMuted),
                const SizedBox(width: 8),
                Text('Admin',
                    style: const TextStyle(
                        fontSize: 13, color: AdminTheme.inkMuted)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 16, color: AdminTheme.inkMuted),
                ),
                Text(_meta[_i].$1,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.ink)),
              ]),
            ),
            AdminIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh',
                onPressed: () => setState(() => _reload++)),
            const SizedBox(width: 12),
            _profileMenu(),
          ],
        ),
      );

  Widget _profileMenu() => PopupMenuButton<String>(
        tooltip: 'Account',
        offset: const Offset(0, 48),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (v) {
          if (v == 'logout') _logout();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'logout',
            child: Row(children: [
              Icon(Icons.logout_rounded, size: 18, color: AppColorsDanger),
              SizedBox(width: 10),
              Text('Sign out'),
            ]),
          ),
        ],
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AdminTheme.accent, Color(0xFFFF7A45)]),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.person_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Administrator',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AdminTheme.ink)),
              Text('Signed in',
                  style: TextStyle(fontSize: 11, color: AdminTheme.inkMuted)),
            ],
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down_rounded,
              color: AdminTheme.inkMuted, size: 20),
        ]),
      );

  // ---------------- Sidebar ----------------
  Widget _sidebar() => Container(
        color: AdminTheme.sidebar,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [AdminTheme.accent, Color(0xFFFF7A45)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.bolt_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppConstants.appName,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    const Text('Admin Console',
                        style: TextStyle(
                            fontSize: 11, color: AdminTheme.sidebarText)),
                  ],
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  for (final section in _sections) ...[
                    if (section.$1.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
                        child: Text(section.$1,
                            style: const TextStyle(
                                fontSize: 10.5,
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B))),
                      )
                    else
                      const SizedBox(height: 4),
                    for (final item in section.$2) _navTile(item),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF1F2937)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: _rawTile(
                icon: Icons.logout_rounded,
                label: 'Sign out',
                color: const Color(0xFFF87171),
                onTap: _logout,
              ),
            ),
          ],
        ),
      );

  Widget _navTile((IconData, String, int) item) {
    final active = _i == item.$3;
    return Builder(builder: (ctx) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: active ? AdminTheme.sidebarPanel : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () {
            setState(() => _i = item.$3);
            final s = Scaffold.maybeOf(ctx);
            if (s != null && s.hasDrawer && s.isDrawerOpen) {
              Navigator.pop(ctx);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(item.$1,
                  size: 20,
                  color: active ? AdminTheme.accent : AdminTheme.sidebarText),
              const SizedBox(width: 13),
              Text(item.$2,
                  style: TextStyle(
                      color: active
                          ? AdminTheme.sidebarActive
                          : AdminTheme.sidebarText,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13.5)),
            ]),
          ),
        ),
      ),
    ));
  }

  Widget _rawTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) =>
      Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 13),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5)),
            ]),
          ),
        ),
      );
}

/// Local alias so the popup can reference the danger colour without an extra
/// import in the const item list.
const AppColorsDanger = Color(0xFFE74C3C);
