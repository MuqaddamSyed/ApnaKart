import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../core/routing/app_router.dart';
import '../../shared/services/bootstrap.dart';
import '../../shared/services/notification_service.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'screens/fast_food_screen.dart';
import 'screens/addresses_screen.dart';
import 'screens/search_screen.dart';
import 'screens/supplier_detail_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/order_tracking_screen.dart';
import 'screens/order_history_screen.dart';
import 'screens/profile_screen.dart';

Future<void> main() async {
  await bootstrap(initializeFirebase: true);
  await NotificationService().initFCM(appRole: 'customer');
  runApp(const ProviderScope(child: CustomerApp()));
}

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: Routes.splash,
      routes: [
        GoRoute(path: Routes.splash, builder: (_, __) => const SplashScreen()),
        GoRoute(path: Routes.login, builder: (_, __) => const LoginScreen()),
        GoRoute(path: Routes.onboarding, builder: (_, __) => const CustomerOnboardingScreen()),
        GoRoute(path: Routes.home, builder: (_, __) => const HomeScreen()),
        GoRoute(path: Routes.fastfood, builder: (_, __) => const FastFoodScreen()),
        GoRoute(
          path: Routes.search,
          builder: (_, s) => SearchScreen(category: s.uri.queryParameters['category']),
        ),
        GoRoute(
          path: '${Routes.supplier}/:id',
          builder: (_, s) => SupplierDetailScreen(supplierId: s.pathParameters['id']!),
        ),
        GoRoute(path: Routes.cart, builder: (_, __) => const CartScreen()),
        GoRoute(
          path: Routes.addresses,
          builder: (_, s) =>
              AddressesScreen(selectMode: s.uri.queryParameters['select'] == '1'),
        ),
        GoRoute(
          path: '${Routes.tracking}/:orderId',
          builder: (_, s) => OrderTrackingScreen(orderId: s.pathParameters['orderId']!),
        ),
        GoRoute(path: Routes.history, builder: (_, __) => const OrderHistoryScreen()),
        GoRoute(path: Routes.profile, builder: (_, __) => const ProfileScreen()),
      ],
    );
    return MaterialApp.router(
      title: '${AppConstants.appName} Customer',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}
