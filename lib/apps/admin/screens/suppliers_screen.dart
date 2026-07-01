import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/supplier.dart';
import '../../../shared/services/supabase_client.dart';
import 'admin_ui.dart';

/// Supplier list with verify toggle, phone number, and product count.
class AdminSuppliersScreen extends StatefulWidget {
  const AdminSuppliersScreen({super.key});
  @override
  State<AdminSuppliersScreen> createState() => _State();
}

class _State extends State<AdminSuppliersScreen> {
  List<_SupplierRow> _rows = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Join with users to get phone; count products per supplier.
    final supplierRows = await supabase
        .from('suppliers')
        .select('*, users(phone)');
    final productCounts = await supabase
        .from('products')
        .select('supplier_id');

    final countMap = <String, int>{};
    for (final p in (productCounts as List)) {
      final sid = p['supplier_id'] as String;
      countMap[sid] = (countMap[sid] ?? 0) + 1;
    }

    if (mounted) {
      setState(() {
        _rows = (supplierRows as List).map((e) {
          final phone = (e['users'] as Map?)?['phone'] as String?;
          final supplier = Supplier.fromMap(e);
          return _SupplierRow(
            supplier: supplier,
            phone: phone,
            productCount: countMap[supplier.id] ?? 0,
          );
        }).toList();
        _loading = false;
      });
    }
  }

  Future<void> _setVerified(Supplier s, bool v) async {
    await supabase
        .from('suppliers')
        .update({'is_verified': v})
        .eq('id', s.id);
    _load();
  }

  Future<void> _setOpen(Supplier s, bool v) async {
    await supabase
        .from('suppliers')
        .update({'is_open': v})
        .eq('id', s.id);
    _load();
  }

  List<_SupplierRow> get _filtered {
    if (_search.isEmpty) return _rows;
    final q = _search.toLowerCase();
    return _rows
        .where((r) =>
            r.supplier.shopName.toLowerCase().contains(q) ||
            (r.supplier.address?.toLowerCase().contains(q) ?? false) ||
            (r.phone?.contains(q) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminPageTitle(
            'Suppliers',
            trailing: Row(children: [
              SizedBox(
                width: 240,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search by name or phone...',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(child: Text('No suppliers found'))
                    : ListView.separated(
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, idx) {
                          final row = _filtered[idx];
                          final s = row.supplier;
                          return AdminCard(
                            child: Row(
                              children: [
                                // Avatar.
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.storefront,
                                      color: AppColors.primary),
                                ),
                                const SizedBox(width: 16),
                                // Details.
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Text(s.shopName,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15)),
                                        const SizedBox(width: 8),
                                        if (s.isVerified)
                                          const Icon(Icons.verified,
                                              size: 16,
                                              color: AppColors.secondary),
                                      ]),
                                      if (s.address != null)
                                        Text(s.address!,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textMuted)),
                                      const SizedBox(height: 4),
                                      Row(children: [
                                        const Icon(Icons.phone_outlined,
                                            size: 14,
                                            color: AppColors.textMuted),
                                        const SizedBox(width: 4),
                                        GestureDetector(
                                          onTap: () {
                                            if (row.phone != null) {
                                              Clipboard.setData(
                                                  ClipboardData(
                                                      text: row.phone!));
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(const SnackBar(
                                                      content: Text(
                                                          'Phone copied')));
                                            }
                                          },
                                          child: Text(
                                            row.phone ?? 'No phone',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: row.phone != null
                                                    ? AppColors.primary
                                                    : AppColors.textMuted,
                                                decoration: row.phone != null
                                                    ? TextDecoration.underline
                                                    : null),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        const Icon(Icons.inventory_2_outlined,
                                            size: 14,
                                            color: AppColors.textMuted),
                                        const SizedBox(width: 4),
                                        Text('${row.productCount} products',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textMuted)),
                                        const SizedBox(width: 12),
                                        Text(s.category.take(2).join(', '),
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textMuted)),
                                      ]),
                                    ],
                                  ),
                                ),
                                // Controls.
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Row(mainAxisSize: MainAxisSize.min, children: [
                                      Text('Verified',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: s.isVerified
                                                  ? AppColors.secondary
                                                  : AppColors.textMuted)),
                                      Switch(
                                        value: s.isVerified,
                                        activeColor: AppColors.secondary,
                                        onChanged: (v) => _setVerified(s, v),
                                      ),
                                    ]),
                                    Row(mainAxisSize: MainAxisSize.min, children: [
                                      Text('Open',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: s.isOpen
                                                  ? AppColors.primary
                                                  : AppColors.textMuted)),
                                      Switch(
                                        value: s.isOpen,
                                        activeColor: AppColors.primary,
                                        onChanged: (v) => _setOpen(s, v),
                                      ),
                                    ]),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SupplierRow {
  final Supplier supplier;
  final String? phone;
  final int productCount;
  const _SupplierRow(
      {required this.supplier,
      required this.phone,
      required this.productCount});
}
