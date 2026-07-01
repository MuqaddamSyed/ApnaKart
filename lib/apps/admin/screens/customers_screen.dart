import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/services/supabase_client.dart';

/// Customer list with block/unblock.
class AdminCustomersScreen extends StatefulWidget {
  const AdminCustomersScreen({super.key});
  @override
  State<AdminCustomersScreen> createState() => _State();
}

class _State extends State<AdminCustomersScreen> {
  List<Map<String, dynamic>> _customers = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    // users row carries whichever contact method the pilot is using.
    final rows = await supabase.from('users').select().eq('role', 'customer');
    _customers = (rows as List).cast<Map<String, dynamic>>();
    setState(() => _loading = false);
  }

  Future<void> _setActive(String id, bool active) async {
    await supabase.from('users').update({'is_active': active}).eq('id', id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Customers', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ..._customers.map((c) {
          final active = c['is_active'] as bool? ?? true;
          return Card(
            child: ListTile(
              leading: const Icon(Icons.person, color: AppColors.primary),
              title: Text(c['name']?.toString() ??
                  c['email']?.toString() ??
                  c['phone']?.toString() ??
                  'Customer'),
              subtitle: Text(c['email']?.toString() ?? c['phone']?.toString() ?? ''),
              trailing: TextButton(
                onPressed: () => _setActive(c['id'] as String, !active),
                child: Text(active ? 'Block' : 'Unblock',
                    style: TextStyle(color: active ? AppColors.danger : AppColors.secondary)),
              ),
            ),
          );
        }),
      ],
    );
  }
}
