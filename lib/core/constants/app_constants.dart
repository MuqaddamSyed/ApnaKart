/// App-wide constants and Phase-1 business rules.
class AppConstants {
  static const appName = 'myMinto';

  // Delivery fee: flat, charged on every order regardless of amount.
  static const double flatDeliveryFee = 10.0;

  // Minimum order value (items subtotal) required to check out.
  static const double minOrderValue = 39.0;

  // Supplier discovery radius
  static const double defaultRadiusKm = 5.0;

  // Discount badge threshold
  static const int discountBadgeMin = 5;
  static const int topDealMin = 20;

  // Agent location ping interval while on delivery
  static const int agentPingSeconds = 10;

  // Incoming order accept window (delivery app)
  static const int acceptWindowSeconds = 15;

  // Customer Home category grid tiles.
  static const List<String> categories = [
    'Vegetables',
    'Fruits',
    'Rice, Atta, Dals - Groceries',
    'Chocolates',
    'Ice Cream',
    'Packaged food',
    'Medical Store',
    'Home Essentials',
  ];

  // Categories a supplier can tag a product / shop with. Includes
  // 'Fast Food', which surfaces on the customer Fast Food tab (not the grid).
  static const List<String> productCategories = [
    ...categories,
    'Fast Food',
  ];

  // Support
  static const String supportWhatsApp = '+919000000000';
}
