import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/validators.dart';

/// Delivery partner onboarding shown after email-OTP sign-in.
/// Collects name + mobile + vehicle + base address and creates the
/// users + delivery_agents rows (unverified until admin approval).
class DeliveryOnboardingScreen extends ConsumerStatefulWidget {
  const DeliveryOnboardingScreen({super.key});
  @override
  ConsumerState<DeliveryOnboardingScreen> createState() => _State();
}

class _State extends ConsumerState<DeliveryOnboardingScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  String _vehicle = 'Bike';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 4) {
      return setState(() => _error = 'Name must be at least 4 characters');
    }
    final phoneErr = Validators.phone(_phone.text);
    if (phoneErr != null) return setState(() => _error = phoneErr);
    if (_address.text.trim().isEmpty) {
      return setState(() => _error = 'Please enter your address');
    }
    setState(() { _saving = true; _error = null; });
    try {
      final email = supabase.auth.currentUser?.email ?? '';
      final phone = Validators.toE164(_phone.text);
      await ref.read(authServiceProvider).ensureUserRow(
            email: email,
            phone: phone,
            name: _name.text.trim(),
            role: 'delivery',
          );
      final uid = supabase.auth.currentUser!.id;
      // Insert unverified — the approval trigger + RLS allow self-insert only
      // while is_verified=false; admin flips it later.
      await supabase.from('delivery_agents').upsert({
        'id': uid,
        'vehicle_type': _vehicle,
        'address': _address.text.trim(),
        'is_available': false,
      });
      await ref.read(notificationServiceProvider).initFCM(appRole: 'delivery');
      if (mounted) context.go(Routes.status);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('Complete your profile'),
          automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Tell us about yourself. An admin verifies your account before you '
            'can go online and accept deliveries.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
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
          const SizedBox(height: 16),
          const Text('Vehicle', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['Bike', 'Scooter', 'Cycle'].map((v) {
              return ChoiceChip(
                label: Text(v),
                selected: _vehicle == v,
                selectedColor: AppColors.primary.withOpacity(0.15),
                onSelected: (_) => setState(() => _vehicle = v),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _address,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Your address',
              hintText: 'Area / locality you operate from',
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
                : const Text('Submit for approval'),
          ),
        ],
      ),
    );
  }
}
