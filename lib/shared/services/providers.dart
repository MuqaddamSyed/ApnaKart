import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_service.dart';
import 'order_service.dart';
import 'product_service.dart';
import 'location_service.dart';
import 'notification_service.dart';

/// Riverpod providers exposing the shared services to all flavors.
final authServiceProvider = Provider((_) => AuthService());
final orderServiceProvider = Provider((_) => OrderService());
final productServiceProvider = Provider((_) => ProductService());
final locationServiceProvider = Provider((_) => LocationService());
final notificationServiceProvider = Provider((_) => NotificationService());

/// Holds the signed-in user's id (set after OTP verify).
final currentUserIdProvider = StateProvider<String?>((_) => null);
