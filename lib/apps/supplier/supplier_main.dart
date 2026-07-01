import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../core/routing/app_router.dart';
import '../../shared/services/bootstrap.dart';
import '../../shared/services/notification_service.dart';
import '../../shared/widgets/otp_login.dart';
import 'screens/dashboard_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/products_screen.dart';
import 'screens/edit_product_screen.dart';
import 'screens/profile_screen.dart';

Future<void> main() async {
  await bootstrap(initializeFirebase: true);
  await NotificationService().initFCM(appRole: 'supplier');
  runApp(const ProviderScope(child: SupplierApp()));
}

class SupplierApp extends StatelessWidget {
  const SupplierApp({super.key});
  @override
  Widget build(BuildContext context) {
    final loggedIn = Supabase.instance.client.auth.currentSession != null;
    final router = GoRouter(
      initialLocation: loggedIn ? Routes.dashboard : Routes.login,
      routes: [
        GoRoute(path: Routes.login, builder: (_, __) => Scaffold(
              body: SafeArea(child: OtpLogin(
                role: 'supplier',
                collectPhone: false,
                onSuccess: (id, isNew) => GoRouter.of(_).go(Routes.dashboard),
              )),
            )),
        GoRoute(path: Routes.dashboard, builder: (_, __) => const SupplierShell()),
        GoRoute(path: Routes.editProduct, builder: (_, s) =>
            EditProductScreen(productId: s.uri.queryParameters['id'])),
      ],
    );
    return MaterialApp.router(
      title: '${AppConstants.appName} Partner',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}

/// Bottom-nav shell: Dashboard | Orders | Products | Profile.
class SupplierShell extends StatefulWidget {
  const SupplierShell({super.key});
  @override
  State<SupplierShell> createState() => _SupplierShellState();
}

class _SupplierShellState extends State<SupplierShell> {
  int _i = 0;
  final _pages = const [
    DashboardScreen(), OrdersScreen(), ProductsScreen(), SupplierProfileScreen(),
  ];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_i],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _i,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFFF4500),
        onTap: (v) => setState(() => _i = v),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Orders'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'Products'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
