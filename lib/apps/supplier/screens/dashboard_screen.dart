import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/order.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';
import 'create_shop_screen.dart';

/// Today's orders/revenue, pending badge, open/closed toggle.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _State();
}

class _State extends ConsumerState<DashboardScreen> {
  bool _open = true;
  bool _approved = false;
  bool _hasShopProfile = false;
  List<Order> _orders = [];
  bool _loading = true;
  double _todayEarnings = 0;
  double _totalEarnings = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid != null) {
      final shop = await supabase.from('suppliers').select('is_open,is_verified').eq('id', uid).maybeSingle();
      _hasShopProfile = shop != null;
      _approved = shop?['is_verified'] as bool? ?? false;
      _open = shop?['is_open'] as bool? ?? true;
      if (_approved) {
        _orders = await ref.read(orderServiceProvider).getOrdersBySupplier(uid);
        _todayEarnings = await ref.read(orderServiceProvider).getTodaySupplierEarnings(uid);
        _totalEarnings = await ref.read(orderServiceProvider).getTotalSupplierEarnings(uid);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleOpen(bool v) async {
    final uid = supabase.auth.currentUser?.id;
    setState(() => _open = v);
    if (uid != null) {
      await supabase.from('suppliers').update({'is_open': v}).eq('id', uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    bool sameDay(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;
    final todaysOrders = _orders.where((o) =>
        sameDay(o.placedAt) &&
        o.status != OrderStatus.cancelled &&
        o.status != OrderStatus.returned).toList();
    final pending = _orders.where((o) => o.status == OrderStatus.placed).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_hasShopProfile
              ? _ApprovalNotice(
                  title: 'Set up your shop',
                  message: 'Create your shop profile to start adding products. An admin verifies it before you go live.',
                  action: ElevatedButton.icon(
                    icon: const Icon(Icons.storefront),
                    label: const Text('Create shop profile'),
                    onPressed: () async {
                      final created = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => const CreateShopScreen()),
                      );
                      if (created == true) _load();
                    },
                  ),
                )
          : !_approved
              ? const _ApprovalNotice(
                  title: 'Waiting for admin approval',
                  message: 'Your supplier account is registered. The shop will appear to customers after admin verification.',
                )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: SwitchListTile(
                      value: _open,
                      activeColor: AppColors.secondary,
                      title: Text(_open ? 'Shop is Open' : 'Shop is Closed'),
                      subtitle: const Text('Toggle availability for new orders'),
                      onChanged: _toggleOpen,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    _stat("Today's Orders", '${todaysOrders.length}', Icons.shopping_bag),
                    const SizedBox(width: 12),
                    _stat("Today's Earnings", formatRupees(_todayEarnings), Icons.payments),
                  ]),
                  const SizedBox(height: 12),
                  // Lifetime earnings across all delivered orders.
                  _stat('Total Earnings', formatRupees(_totalEarnings),
                      Icons.account_balance_wallet,
                      full: true, color: AppColors.secondary),
                  const SizedBox(height: 12),
                  _stat('Pending Orders', '$pending', Icons.pending_actions, full: true,
                      color: pending > 0 ? AppColors.warning : AppColors.secondary),
                ],
              ),
            ),
    );
  }

  Widget _stat(String label, String value, IconData icon,
      {bool full = false, Color color = AppColors.primary}) {
    final card = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
    return full ? card : Expanded(child: card);
  }
}

class _ApprovalNotice extends StatelessWidget {
  final String title;
  final String message;
  final Widget? action;
  const _ApprovalNotice({required this.title, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_user_outlined, color: AppColors.warning, size: 48),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
