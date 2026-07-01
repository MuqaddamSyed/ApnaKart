import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/address.dart';
import '../../../shared/services/address_service.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/validators.dart';

/// Manage saved delivery addresses: add / edit / delete / set default.
class AddressesScreen extends ConsumerStatefulWidget {
  /// When true, tapping an address selects it as default and pops (picker mode).
  final bool selectMode;
  const AddressesScreen({super.key, this.selectMode = false});
  @override
  ConsumerState<AddressesScreen> createState() => _State();
}

class _State extends ConsumerState<AddressesScreen> {
  List<Address> _addresses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    _addresses = await ref.read(addressServiceProvider).list(uid);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openForm({Address? existing}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddressFormScreen(existing: existing)),
    );
    if (changed == true) {
      await _load();
      await ref.read(currentAddressProvider.notifier).refresh();
    }
  }

  Future<void> _delete(Address a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete address?'),
        content: Text(a.fullAddress ?? ''),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(addressServiceProvider).delete(a.id);
    await _load();
  }

  Future<void> _setDefault(Address a) async {
    await ref.read(currentAddressProvider.notifier).setDefault(a);
    if (!mounted) return;
    if (widget.selectMode) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Default address updated')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentAddressProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.selectMode ? 'Select address' : 'My Addresses')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add),
        label: const Text('Add address'),
        onPressed: () => _openForm(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _addresses.isEmpty
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.location_off_outlined, size: 44, color: AppColors.textMuted),
                    SizedBox(height: 8),
                    Text('No saved addresses yet', style: TextStyle(color: AppColors.textMuted)),
                  ]),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: _addresses.map((a) {
                    final isDefault = current?.text == a.fullAddress;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.location_on_outlined,
                                  color: AppColors.primary, size: 20),
                              const SizedBox(width: 6),
                              Text(a.label ?? 'Address',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(width: 8),
                              if (isDefault)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.secondary.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text('DEFAULT',
                                      style: TextStyle(
                                          color: AppColors.secondary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700)),
                                ),
                            ]),
                            const SizedBox(height: 6),
                            Text(a.fullAddress ?? '',
                                style: const TextStyle(color: AppColors.textMuted)),
                            const SizedBox(height: 8),
                            Row(children: [
                              if (!isDefault)
                                TextButton.icon(
                                  onPressed: () => _setDefault(a),
                                  icon: const Icon(Icons.check_circle_outline, size: 18),
                                  label: Text(widget.selectMode ? 'Deliver here' : 'Set default'),
                                ),
                              if (isDefault && widget.selectMode)
                                TextButton.icon(
                                  onPressed: () => Navigator.pop(context, true),
                                  icon: const Icon(Icons.check_circle, size: 18, color: AppColors.secondary),
                                  label: const Text('Deliver here'),
                                ),
                              const Spacer(),
                              IconButton(
                                onPressed: () => _openForm(existing: a),
                                icon: const Icon(Icons.edit_outlined, size: 20),
                              ),
                              IconButton(
                                onPressed: () => _delete(a),
                                icon: const Icon(Icons.delete_outline,
                                    size: 20, color: AppColors.danger),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
    );
  }
}

/// Add/edit a single address. Pops `true` when saved.
class AddressFormScreen extends ConsumerStatefulWidget {
  final Address? existing;
  const AddressFormScreen({super.key, this.existing});
  @override
  ConsumerState<AddressFormScreen> createState() => _FormState();
}

class _FormState extends ConsumerState<AddressFormScreen> {
  late final TextEditingController _label;
  late final TextEditingController _full;
  double? _lat;
  double? _lng;
  bool _locating = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _label = TextEditingController(text: e?.label ?? 'Home');
    _full = TextEditingController(text: e?.fullAddress ?? '');
    _lat = e?.lat;
    _lng = e?.lng;
  }

  @override
  void dispose() {
    _label.dispose();
    _full.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() { _locating = true; _error = null; });
    try {
      final pos = await ref.read(locationServiceProvider).getCurrentLocation();
      setState(() { _lat = pos.latitude; _lng = pos.longitude; });
    } catch (e) {
      setState(() => _error = 'Could not get location: $e');
    } finally {
      setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (Validators.notEmpty(_full.text) != null) {
      return setState(() => _error = 'Please enter the full address');
    }
    setState(() { _saving = true; _error = null; });
    try {
      final uid = supabase.auth.currentUser!.id;
      final svc = ref.read(addressServiceProvider);
      final label = _label.text.trim().isEmpty ? 'Home' : _label.text.trim();
      if (widget.existing == null) {
        final a = await svc.add(
          customerId: uid, label: label, fullAddress: _full.text.trim(), lat: _lat, lng: _lng);
        // First address becomes the default automatically.
        final existing = await svc.list(uid);
        if (existing.length == 1) {
          await ref.read(currentAddressProvider.notifier).setDefault(a);
        }
      } else {
        await svc.update(widget.existing!.id,
            label: label, fullAddress: _full.text.trim(), lat: _lat, lng: _lng);
      }
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
      appBar: AppBar(title: Text(widget.existing == null ? 'Add address' : 'Edit address')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Label', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['Home', 'Work', 'Other'].map((l) {
              final selected = _label.text == l;
              return ChoiceChip(
                label: Text(l),
                selected: selected,
                selectedColor: AppColors.primary.withOpacity(0.15),
                onSelected: (_) => setState(() => _label.text = l),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _full,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Full address',
              hintText: 'House / flat, street, area, landmark, city, pincode',
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.my_location, color: AppColors.primary),
              title: Text(hasLocation ? 'Location pinned' : 'Pin location (optional)'),
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
              child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save address'),
          ),
        ],
      ),
    );
  }
}
