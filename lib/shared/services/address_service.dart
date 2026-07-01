import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/address.dart';
import 'supabase_client.dart';

/// CRUD for a customer's saved delivery addresses + the default selection.
/// The chosen default is denormalised onto customers.default_* so checkout
/// and the home bar can read it cheaply.
class AddressService {
  Future<List<Address>> list(String customerId) async {
    final rows = await supabase
        .from('addresses')
        .select()
        .eq('customer_id', customerId)
        .order('id');
    return (rows as List).map((e) => Address.fromMap(e)).toList();
  }

  Future<Address> add({
    required String customerId,
    String? label,
    required String fullAddress,
    double? lat,
    double? lng,
  }) async {
    final row = await supabase.from('addresses').insert({
      'customer_id': customerId,
      'label': label,
      'full_address': fullAddress,
      'lat': lat,
      'lng': lng,
    }).select().single();
    return Address.fromMap(row);
  }

  Future<void> update(
    String id, {
    String? label,
    required String fullAddress,
    double? lat,
    double? lng,
  }) async {
    await supabase.from('addresses').update({
      'label': label,
      'full_address': fullAddress,
      'lat': lat,
      'lng': lng,
    }).eq('id', id);
  }

  Future<void> delete(String id) async {
    await supabase.from('addresses').delete().eq('id', id);
  }

  /// Marks [a] as the delivery default (copied onto the customers row).
  Future<void> setDefault(String customerId, Address a) async {
    await supabase.from('customers').update({
      'default_address': a.fullAddress,
      'default_lat': a.lat,
      'default_lng': a.lng,
    }).eq('id', customerId);
  }

  Future<CurrentAddress?> loadDefault(String customerId) async {
    final row = await supabase
        .from('customers')
        .select('default_address,default_lat,default_lng')
        .eq('id', customerId)
        .maybeSingle();
    final text = row?['default_address'] as String?;
    if (text == null || text.isEmpty) return null;
    return CurrentAddress(
      text: text,
      lat: (row?['default_lat'] as num?)?.toDouble(),
      lng: (row?['default_lng'] as num?)?.toDouble(),
    );
  }
}

/// The customer's currently-selected delivery address (denormalised default).
class CurrentAddress {
  final String text;
  final double? lat;
  final double? lng;
  const CurrentAddress({required this.text, this.lat, this.lng});
}

final addressServiceProvider = Provider((_) => AddressService());

/// Reactive holder for the current delivery address. Widgets watch this so the
/// home bar + checkout update immediately when the default changes.
class CurrentAddressNotifier extends StateNotifier<CurrentAddress?> {
  CurrentAddressNotifier(this._ref) : super(null);
  final Ref _ref;

  Future<void> refresh() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      state = null;
      return;
    }
    state = await _ref.read(addressServiceProvider).loadDefault(uid);
  }

  /// Set [a] as default and reflect it immediately.
  Future<void> setDefault(Address a) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    await _ref.read(addressServiceProvider).setDefault(uid, a);
    state = CurrentAddress(text: a.fullAddress ?? '', lat: a.lat, lng: a.lng);
  }
}

final currentAddressProvider =
    StateNotifierProvider<CurrentAddressNotifier, CurrentAddress?>(
        (ref) => CurrentAddressNotifier(ref));
