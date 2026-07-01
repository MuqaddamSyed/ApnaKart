import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/supplier.dart';
import 'supabase_client.dart';

/// Geolocation + PostGIS supplier discovery + distance helpers.
class LocationService {
  /// Current device location (asks for permission if needed).
  Future<LatLng> getCurrentLocation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw Exception('Location permission denied');
    }
    final pos = await Geolocator.getCurrentPosition();
    return LatLng(pos.latitude, pos.longitude);
  }

  /// Suppliers within [radiusKm] using the `nearby_suppliers` PostGIS RPC.
  Future<List<Supplier>> getNearbySuppliers(
    double lat,
    double lng, {
    double radiusKm = 5,
  }) async {
    final rows = await supabase.rpc('nearby_suppliers', params: {
      'user_lng': lng,
      'user_lat': lat,
      'radius_m': radiusKm * 1000,
    });
    return (rows as List).map((e) => Supplier.fromMap(e)).toList();
  }

  /// Pushes an agent's live location (called every ~10s on delivery).
  Future<void> updateAgentLocation(String agentId, double lat, double lng) async {
    await supabase.from('delivery_agents').update({
      'current_lat': lat,
      'current_lng': lng,
    }).eq('id', agentId);
  }

  /// Haversine distance in km.
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    final meters = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
    return meters / 1000.0;
  }

  /// Rough ETA in minutes assuming ~20km/h town speed + 5 min handling.
  int etaMinutes(double distanceKm) => (distanceKm / 20 * 60).round() + 5;
}
