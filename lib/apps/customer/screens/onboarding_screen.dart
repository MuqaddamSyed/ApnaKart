import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/address_service.dart';
import '../../../shared/services/location_service.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/validators.dart';

/// Customer onboarding shown right after email-OTP sign-in.
/// Collects phone + delivery address, creates the users + customers rows.
class CustomerOnboardingScreen extends ConsumerStatefulWidget {
  const CustomerOnboardingScreen({super.key});
  @override
  ConsumerState<CustomerOnboardingScreen> createState() => _State();
}

class _State extends ConsumerState<CustomerOnboardingScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _house = TextEditingController();   // house / flat / street
  final _area = TextEditingController();    // area / locality
  final _landmark = TextEditingController();
  final _city = TextEditingController();
  final _pincode = TextEditingController();
  double? _lat;
  double? _lng;
  bool _locating = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _house, _area, _landmark, _city, _pincode]) {
      c.dispose();
    }
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

  String _composeAddress() {
    final parts = [
      _house.text.trim(),
      _area.text.trim(),
      if (_landmark.text.trim().isNotEmpty) 'Near ${_landmark.text.trim()}',
      _city.text.trim(),
      _pincode.text.trim(),
    ].where((p) => p.isNotEmpty).toList();
    return parts.join(', ');
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 4) {
      return setState(() => _error = 'Name must be at least 4 characters');
    }
    final phoneErr = Validators.phone(_phone.text);
    if (phoneErr != null) return setState(() => _error = phoneErr);
    if (_house.text.trim().isEmpty || _area.text.trim().isEmpty ||
        _city.text.trim().isEmpty || _pincode.text.trim().isEmpty) {
      return setState(() => _error = 'Please fill house/street, area, city and pincode');
    }
    setState(() { _saving = true; _error = null; });
    try {
      final email = supabase.auth.currentUser?.email ?? '';
      final phone = Validators.toE164(_phone.text);
      // Creates/updates the users row (role=customer). Throws if the phone
      // is already registered to another account.
      await ref.read(authServiceProvider).ensureUserRow(
            email: email,
            phone: phone,
            name: _name.text.trim(),
            role: 'customer',
          );
      final uid = supabase.auth.currentUser!.id;
      final address = _composeAddress();
      await supabase.from('customers').upsert({
        'id': uid,
        'default_address': address,
        'default_lat': _lat,
        'default_lng': _lng,
      });
      await supabase.from('addresses').insert({
        'customer_id': uid,
        'label': 'Home',
        'full_address': address,
        'lat': _lat,
        'lng': _lng,
      });
      await ref.read(notificationServiceProvider).initFCM(appRole: 'customer');
      await ref.read(currentAddressProvider.notifier).refresh();
      if (mounted) context.go(Routes.home);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation = _lat != null && _lng != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Complete your profile'), automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Add your phone number and delivery address so we can bring orders to you.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Your name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              prefixText: '+91 ',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const Divider(height: 32),
          const Text('Delivery address', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
            controller: _house,
            decoration: const InputDecoration(labelText: 'House / Flat no., Street name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _area,
            decoration: const InputDecoration(labelText: 'Area / Locality'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _landmark,
            decoration: const InputDecoration(labelText: 'Landmark (optional)'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(
              controller: _city,
              decoration: const InputDecoration(labelText: 'City'),
            )),
            const SizedBox(width: 12),
            Expanded(child: TextField(
              controller: _pincode,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Pincode'),
            )),
          ]),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.my_location, color: AppColors.primary),
              title: Text(hasLocation ? 'Location pinned' : 'Pin my location (optional)'),
              subtitle: Text(hasLocation
                  ? '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'
                  : 'Helps the delivery agent find you'),
              trailing: _locating
                  ? const SizedBox(height: 18, width: 18,
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
                ? const SizedBox(height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save & Continue'),
          ),
        ],
      ),
    );
  }
}
