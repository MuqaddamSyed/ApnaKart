import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/supplier.dart';
import 'supabase_client.dart';

/// Why a location fix could not be produced. Lets the UI react specifically
/// (e.g. offer to open settings) instead of showing a raw exception string.
enum LocationFailureReason { serviceOff, denied, deniedForever, timeout }

class LocationFailure implements Exception {
  final LocationFailureReason reason;
  const LocationFailure(this.reason);

  String get message => switch (reason) {
        LocationFailureReason.serviceOff =>
          'Location (GPS) is turned off. Please turn it on.',
        LocationFailureReason.denied => 'Location permission was denied.',
        LocationFailureReason.deniedForever =>
          'Location permission is blocked. Allow it in app settings.',
        LocationFailureReason.timeout =>
          'Could not get a GPS fix. Move to an open area and retry.',
      };

  /// Whether "open settings" is the fix (vs just retrying).
  bool get settingsCanFix =>
      reason == LocationFailureReason.serviceOff ||
      reason == LocationFailureReason.deniedForever;

  @override
  String toString() => message;
}

/// A location with its accuracy so callers can judge fix quality —
/// a 1500m cell-tower fix must not be trusted like a 5m GPS fix.
class LocationFix {
  final double latitude;
  final double longitude;
  final double accuracyM;
  const LocationFix(this.latitude, this.longitude, this.accuracyM);

  LatLng get latLng => LatLng(latitude, longitude);

  /// Good enough to pin a delivery address on.
  bool get isPrecise => accuracyM <= 150;
}

/// Geolocation + PostGIS supplier discovery + distance helpers.
class LocationService {
  /// Full pre-flight (service on, permission granted) + a high-accuracy fix
  /// with a hard time limit so callers can never hang indefinitely.
  /// Throws [LocationFailure] with a user-presentable reason.
  Future<LocationFix> getFix(
      {Duration timeLimit = const Duration(seconds: 15)}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(LocationFailureReason.serviceOff);
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      throw const LocationFailure(LocationFailureReason.deniedForever);
    }
    if (perm == LocationPermission.denied) {
      throw const LocationFailure(LocationFailureReason.denied);
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: timeLimit,
      );
      return LocationFix(pos.latitude, pos.longitude, pos.accuracy);
    } on TimeoutException {
      // Indoors/weak GPS: a recent cached fix beats nothing, but keep its
      // real accuracy so callers can still judge it.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return LocationFix(last.latitude, last.longitude, last.accuracy);
      }
      throw const LocationFailure(LocationFailureReason.timeout);
    }
  }

  /// Back-compat helper for callers that only need a point (e.g. browsing).
  Future<LatLng> getCurrentLocation() async => (await getFix()).latLng;

  /// Opens whichever system screen fixes [f] (GPS toggle or app permissions).
  Future<void> openSystemSettings(LocationFailure f) =>
      f.reason == LocationFailureReason.serviceOff
          ? Geolocator.openLocationSettings()
          : Geolocator.openAppSettings();

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
  /// Stamps location_updated_at so readers can detect a stale pin.
  Future<void> updateAgentLocation(String agentId, double lat, double lng) async {
    await supabase.from('delivery_agents').update({
      'current_lat': lat,
      'current_lng': lng,
      'location_updated_at': DateTime.now().toUtc().toIso8601String(),
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
