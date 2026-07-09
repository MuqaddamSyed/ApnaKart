import 'package:flutter/foundation.dart' show kIsWeb;

/// MapTiler raster tiles (free tier) used by the embedded maps.
///
/// Two keys, each locked down in the MapTiler dashboard so a leaked key is
/// useless elsewhere:
///   * Web admin  -> key restricted to the admin's HTTP origins
///     (myminto-admin.vercel.app, localhost, 127.0.0.1).
///   * Mobile apps -> key restricted by User-Agent substring "com.quickkart"
///     (flutter_map sends `flutter_map (com.quickkart.<flavor>)`).
///
/// Keys are client-side (they ship inside the build); the dashboard
/// restrictions + the Free-plan usage cap are the real protection. Rotate here.
class MapConfig {
  static const _webKey = 'pD7yH2eWaEQURkWGVrgA';
  static const _appsKey = 'bJvrEEVJGcApIIULegAk';

  /// The platform-appropriate key. `kIsWeb` is a compile-time constant, so the
  /// web build embeds only the web key and the APKs only the apps key.
  static const maptilerKey = kIsWeb ? _webKey : _appsKey;

  /// 256px raster tiles, so flutter_map's default tileSize (256) renders at the
  /// correct zoom with no zoomOffset needed. `streets-v2` is a full street map.
  static const tileUrl =
      'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=$maptilerKey';

  /// Attribution required by the MapTiler and OpenStreetMap terms of use.
  /// (SimpleAttributionWidget already prefixes "© ", so no leading symbol.)
  static const attribution = 'MapTiler · OpenStreetMap contributors';
}
