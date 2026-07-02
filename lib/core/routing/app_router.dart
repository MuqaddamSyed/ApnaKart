import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lightweight route name registry shared across flavors.
/// Each flavor builds its own GoRouter from its screen list; this
/// file centralises the path strings + a session redirect helper.
class Routes {
  static const splash = '/';
  static const login = '/login';
  static const onboarding = '/onboarding';
  static const home = '/home';
  static const fastfood = '/fastfood';
  static const search = '/search';
  static const supplier = '/supplier';   // /supplier/:id
  static const cart = '/cart';
  static const addresses = '/addresses';
  static const tracking = '/tracking';    // /tracking/:sessionId
  static const history = '/history';
  static const profile = '/profile';

  // supplier app
  static const dashboard = '/dashboard';
  static const orders = '/orders';
  static const products = '/products';
  static const editProduct = '/products/edit';
  static const earnings = '/earnings';

  // delivery app
  static const status = '/status';
  static const active = '/active';        // /active/:sessionId

  // admin app
  static const overview = '/overview';
  static const adminOrders = '/admin/orders';
  static const adminSuppliers = '/admin/suppliers';
  static const adminAgents = '/admin/agents';
  static const adminCustomers = '/admin/customers';
  static const adminModeration = '/admin/moderation';
  static const analytics = '/admin/analytics';
}

/// Returns login route if no session, else null (no redirect).
String? authRedirect(GoRouterState state) {
  final session = Supabase.instance.client.auth.currentSession;
  final loggingIn = state.matchedLocation == Routes.login ||
      state.matchedLocation == Routes.splash;
  if (session == null && !loggingIn) return Routes.login;
  return null;
}
