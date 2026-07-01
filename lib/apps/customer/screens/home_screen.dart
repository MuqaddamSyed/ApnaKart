import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/models/supplier.dart';
import '../../../shared/models/product.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/address_service.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/cart_bar.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Home: location bar, banners, category pills, nearby suppliers, top deals.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Demo fallback location (Davangere) if device location unavailable.
  double _lat = 14.4644, _lng = 75.9218;
  bool _loading = true;
  List<Supplier> _suppliers = [];
  List<Product> _deals = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Load the saved delivery address for the top bar (reactive).
    ref.read(currentAddressProvider.notifier).refresh();
    try {
      try {
        final loc = await ref.read(locationServiceProvider).getCurrentLocation();
        _lat = loc.latitude; _lng = loc.longitude;
      } catch (_) {/* keep fallback */}
      final suppliers = await ref
          .read(locationServiceProvider)
          .getNearbySuppliers(_lat, _lng, radiusKm: AppConstants.defaultRadiusKm);
      final deals = await ref.read(productServiceProvider).topDeals(minDiscount: AppConstants.topDealMin);
      setState(() { _suppliers = suppliers; _deals = deals; });
    } catch (_) {
    } finally {
      setState(() => _loading = false);
    }
  }

  void _onNav(int i) {
    switch (i) {
      case 0: break; // already on Home
      case 1: context.push(Routes.fastfood); break;
      case 2: context.push(Routes.search); break;
      case 3: context.push(Routes.history); break;
      case 4: context.push(Routes.profile); break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: GestureDetector(
          onTap: () async {
            await context.push(Routes.addresses);
            ref.read(currentAddressProvider.notifier).refresh();
          },
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              const Icon(Icons.location_on, color: AppColors.primary, size: 20),
              const SizedBox(width: 4),
              Flexible(
                child: Builder(builder: (_) {
                  final addr = ref.watch(currentAddressProvider);
                  return Text(
                    addr?.text ?? 'Set delivery address',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  );
                }),
              ),
              const Icon(Icons.keyboard_arrow_down, size: 20),
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: GestureDetector(
              onTap: () => context.push(Routes.search),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.search, color: AppColors.textMuted, size: 20),
                    SizedBox(width: 8),
                    Text('Search for atta, milk, eggs…',
                        style: TextStyle(color: AppColors.textMuted)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const SkeletonList()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _banner(),
                  const SizedBox(height: 20),
                  _sectionTitle('Shop by category'),
                  _categoryGrid(),
                  const SizedBox(height: 20),
                  _sectionTitle('Nearby Suppliers'),
                  ..._suppliers.map(_supplierTile),
                  if (_suppliers.isEmpty) _empty('No suppliers within 5 km yet'),
                  const SizedBox(height: 20),
                  _sectionTitle('Top Deals'),
                  _deals.isEmpty
                      ? _empty('No deals right now')
                      : SizedBox(
                          height: 150,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: _deals.map(_dealCard).toList(),
                          ),
                        ),
                ],
              ),
            ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CartBar(),
          BottomNavigationBar(
            currentIndex: 0,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: AppColors.textMuted,
            onTap: _onNav,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(icon: Icon(Icons.fastfood), label: 'Fast Food'),
              BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
              BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Orders'),
              BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _banner() => Container(
        height: 120,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [AppColors.primary, Color(0xFFFF7A40)]),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Groceries in minutes',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            Text('Flat Rs.10 delivery on every order',
                style: TextStyle(color: Colors.white70)),
          ],
        ),
      );

  // Each category maps to a tile image. Fruits reuses the veg/fruit basket.
  static const _categoryImages = {
    'Vegetables': 'assets/images/categories/vegetables.jpg',
    'Fruits': 'assets/images/categories/vegetables.jpg',
    'Rice, Atta, Dals - Groceries': 'assets/images/categories/groceries.jpg',
    'Chocolates': 'assets/images/categories/chocolates.jpg',
    'Ice Cream': 'assets/images/categories/icecream.jpg',
    'Packaged food': 'assets/images/categories/packaged.jpg',
    'Medical Store': 'assets/images/categories/medical.jpg',
    'Home Essentials': 'assets/images/categories/essentials.jpg',
  };

  String _catLabel(String c) =>
      c == 'Rice, Atta, Dals - Groceries' ? 'Atta, Rice, Dal' : c;

  Widget _categoryGrid() => GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 14,
        crossAxisSpacing: 10,
        childAspectRatio: 0.72,
        children: [
          for (final c in AppConstants.categories)
            _categoryTile(
              label: _catLabel(c),
              imagePath: _categoryImages[c],
              onTap: () =>
                  context.push('${Routes.search}?category=${Uri.encodeComponent(c)}'),
            ),
          // Fast Food gets its own dedicated screen (grouped by shop).
          _categoryTile(
            label: 'Fast Food',
            icon: Icons.fastfood,
            onTap: () => context.push(Routes.fastfood),
          ),
        ],
      );

  Widget _categoryTile({
    required String label,
    String? imagePath,
    IconData? icon,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: imagePath != null
                  ? Image.asset(
                      imagePath,
                      width: 62,
                      height: 62,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _iconTile(icon ?? Icons.category),
                    )
                  : _iconTile(icon ?? Icons.category),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, height: 1.1),
            ),
          ],
        ),
      );

  Widget _iconTile(IconData icon) => Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: AppColors.primary, size: 28),
      );

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );

  Widget _supplierTile(Supplier s) => Card(
        child: ListTile(
          leading: const CircleAvatar(
              backgroundColor: AppColors.background,
              child: Icon(Icons.storefront, color: AppColors.primary)),
          title: Text(s.shopName),
          subtitle: Text(s.category.join(', ')),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: s.isOpen ? AppColors.secondary : AppColors.danger,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(s.isOpen ? 'Open' : 'Closed',
                    style: const TextStyle(color: Colors.white, fontSize: 10)),
              ),
              const SizedBox(height: 4),
              if (s.rating <= 0)
                const Text('New', style: TextStyle(fontSize: 12, color: AppColors.textMuted))
              else
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star, size: 12, color: AppColors.warning),
                  Text(' ${s.rating.toStringAsFixed(1)}', style: const TextStyle(fontSize: 12)),
                ]),
            ],
          ),
          onTap: () => context.push('${Routes.supplier}/${s.id}'),
        ),
      );

  Widget _dealCard(Product p) => GestureDetector(
        onTap: () => context.push('${Routes.supplier}/${p.supplierId}'),
        child: Container(
          width: 140,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: SizedBox(
                      height: 80,
                      width: double.infinity,
                      child: p.imageUrl == null
                          ? Container(
                              color: AppColors.background,
                              child: const Icon(Icons.shopping_bag_outlined,
                                  color: AppColors.textMuted))
                          : CachedNetworkImage(
                              imageUrl: p.imageUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) =>
                                  Container(color: AppColors.background),
                              errorWidget: (_, __, ___) => Container(
                                  color: AppColors.background,
                                  child: const Icon(Icons.image_not_supported_outlined,
                                      color: AppColors.textMuted)),
                            ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.secondary,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('${p.discountPercent}% OFF',
                          style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Text(formatRupees(p.salePrice),
                          style: const TextStyle(
                              color: AppColors.primary, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 4),
                      Text(formatRupees(p.mrp),
                          style: const TextStyle(
                              decoration: TextDecoration.lineThrough,
                              fontSize: 11,
                              color: AppColors.textMuted)),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _empty(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(
            children: [
              const Icon(Icons.inbox_outlined, size: 40, color: AppColors.textMuted),
              const SizedBox(height: 8),
              Text(t, textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted)),
            ],
          ),
        ),
      );
}
