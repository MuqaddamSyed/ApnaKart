import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/supplier.dart';
import '../../../shared/services/supabase_client.dart';

/// Supplier list with verify/suspend toggles.
class AdminSuppliersScreen extends StatefulWidget {
  const AdminSuppliersScreen({super.key});
  @override
  State<AdminSuppliersScreen> createState() => _State();
}

class _State extends State<AdminSuppliersScreen> {
  List<Supplier> _suppliers = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final rows = await supabase.from('suppliers').select();
    _suppliers = (rows as List).map((e) => Supplier.fromMap(e)).toList();
    setState(() => _loading = false);
  }

  Future<void> _setVerified(Supplier s, bool v) async {
    await supabase.from('suppliers').update({'is_verified': v}).eq('id', s.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Suppliers', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ..._suppliers.map((s) => Card(
              child: ListTile(
                leading: const Icon(Icons.storefront, color: AppColors.primary),
                title: Text(s.shopName),
                subtitle: Text('${s.address ?? ''}  •  ${s.category.join(', ')}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(s.isVerified ? 'Verified' : 'Unverified',
                      style: TextStyle(
                          color: s.isVerified ? AppColors.secondary : AppColors.warning,
                          fontSize: 12)),
                  Switch(
                    value: s.isVerified,
                    activeColor: AppColors.secondary,
                    onChanged: (v) => _setVerified(s, v),
                  ),
                ]),
              ),
            )),
      ],
    );
  }
}
