import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/services/location_service.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/validators.dart';

/// Supplier onboarding: collects owner name + phone and creates the
/// `suppliers` shop profile. Inserts unverified; admin verifies later.
class CreateShopScreen extends ConsumerStatefulWidget {
  const CreateShopScreen({super.key});
  @override
  ConsumerState<CreateShopScreen> createState() => _State();
}

class _State extends ConsumerState<CreateShopScreen> {
  final _ownerName = TextEditingController();
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final Set<String> _categories = {};
  double? _lat;
  double? _lng;
  bool _locating = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _ownerName.dispose();
    _phone.dispose();
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() { _locating = true; _error = null; });
    final svc = ref.read(locationServiceProvider);
    try {
      final fix = await svc.getFix();
      setState(() { _lat = fix.latitude; _lng = fix.longitude; });
      if (!fix.isPrecise && mounted) {
        // Coarse fix: usable, but tell the user so they can improve it.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Location is approximate (±${fix.accuracyM.round()}m). '
                'Move to an open area and tap again for a precise pin.')));
      }
    } on LocationFailure catch (f) {
      setState(() => _error = f.message);
      if (f.settingsCanFix && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(f.message),
          action: SnackBarAction(
              label: 'SETTINGS', onPressed: () => svc.openSystemSettings(f)),
        ));
      }
    } catch (e) {
      setState(() => _error = 'Could not get location: $e');
    } finally {
      setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (_ownerName.text.trim().length < 4) {
      return setState(() => _error = 'Name must be at least 4 characters');
    }
    final phoneErr = Validators.phone(_phone.text);
    if (phoneErr != null) return setState(() => _error = phoneErr);
    if (_name.text.trim().isEmpty) {
      return setState(() => _error = 'Shop name is required');
    }
    if (_categories.isEmpty) {
      return setState(() => _error = 'Pick at least one category');
    }
    setState(() { _saving = true; _error = null; });
    try {
      final email = supabase.auth.currentUser?.email ?? '';
      // Create the users row (name + phone) before the shop profile.
      await ref.read(authServiceProvider).ensureUserRow(
            email: email,
            phone: Validators.toE164(_phone.text),
            name: _ownerName.text.trim(),
            role: 'supplier',
          );
      final uid = supabase.auth.currentUser!.id;
      await supabase.from('suppliers').insert({
        'id': uid,
        'shop_name': _name.text.trim(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'category': _categories.toList(),
        'lat': _lat,
        'lng': _lng,
      });
      await ref.read(notificationServiceProvider).initFCM(appRole: 'supplier');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation = _lat != null && _lng != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Create shop profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Set up your shop. After you submit, an admin verifies it before '
            'your shop and products go live to customers.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          const Text('Your details', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _ownerName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Full name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Mobile number',
              prefixText: '+91 ',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const Divider(height: 32),
          const Text('Shop details', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Shop name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Address'),
          ),
          const SizedBox(height: 16),
          const Text('Categories', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: AppConstants.productCategories.map((c) {
              final selected = _categories.contains(c);
              return FilterChip(
                label: Text(c),
                selected: selected,
                selectedColor: AppColors.primary.withOpacity(0.15),
                checkmarkColor: AppColors.primary,
                onSelected: (v) => setState(() =>
                    v ? _categories.add(c) : _categories.remove(c)),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.my_location, color: AppColors.primary),
              title: Text(hasLocation
                  ? 'Location set'
                  : 'Set shop location'),
              subtitle: Text(hasLocation
                  ? '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'
                  : 'Used to show your shop to nearby customers'),
              trailing: _locating
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(
                      onPressed: _useCurrentLocation,
                      child: Text(hasLocation ? 'Update' : 'Use current'),
                    ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18, width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Submit for approval'),
          ),
        ],
      ),
    );
  }
}
