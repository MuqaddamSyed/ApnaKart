import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../core/routing/app_router.dart';
import '../../shared/services/bootstrap.dart';
import '../../shared/services/notification_service.dart';
import '../../shared/services/supabase_client.dart';
import '../../shared/widgets/otp_login.dart';
import 'screens/status_screen.dart';
import 'screens/active_delivery_screen.dart';
import 'screens/earnings_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/onboarding_screen.dart';

/// After OTP: new agents (no delivery_agents row) go to onboarding.
Future<void> _routeAfterLogin(BuildContext context, String id) async {
  final row = await supabase
      .from('delivery_agents')
      .select('id')
      .eq('id', id)
      .maybeSingle();
  if (!context.mounted) return;
  GoRouter.of(context).go(row == null ? Routes.onboarding : Routes.status);
}

Future<void> main() async {
  await bootstrap(initializeFirebase: true);
  await NotificationService().initFCM(appRole: 'delivery');
  runApp(const ProviderScope(child: DeliveryApp()));
}

class DeliveryApp extends StatelessWidget {
  const DeliveryApp({super.key});
  @override
  Widget build(BuildContext context) {
    final loggedIn = Supabase.instance.client.auth.currentSession != null;
    final router = GoRouter(
      initialLocation: loggedIn ? Routes.status : Routes.login,
      routes: [
        GoRoute(path: Routes.login, builder: (_, __) => Scaffold(
              body: SafeArea(child: OtpLogin(
                role: 'delivery',
                collectPhone: false,
                onSuccess: (id, isNew) => _routeAfterLogin(_, id),
              )),
            )),
        GoRoute(path: Routes.onboarding, builder: (_, __) => const DeliveryOnboardingScreen()),
        GoRoute(path: Routes.status, builder: (_, __) => const DeliveryShell()),
        GoRoute(path: '${Routes.active}/:orderId',
            builder: (_, s) => ActiveDeliveryScreen(orderId: s.pathParameters['orderId']!)),
      ],
    );
    return MaterialApp.router(
      title: '${AppConstants.appName} Delivery',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}

class DeliveryShell extends StatefulWidget {
  const DeliveryShell({super.key});
  @override
  State<DeliveryShell> createState() => _DeliveryShellState();
}

class _DeliveryShellState extends State<DeliveryShell> {
  int _i = 0;
  final _pages = const [StatusScreen(), DeliveryEarningsScreen(), DeliveryProfileScreen()];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_i],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _i,
        selectedItemColor: const Color(0xFFFF4500),
        onTap: (v) => setState(() => _i = v),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Earnings'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
