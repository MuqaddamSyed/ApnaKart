/// MapTiler raster tiles (free tier) used by the embedded maps.
///
/// The key is a CLIENT key — it ships inside the APK/web build and is therefore
/// public by design. Protect it in the MapTiler dashboard with a monthly usage
/// limit and (for the web admin) an allowed-origin restriction. Rotate here if
/// it ever needs changing.
class MapConfig {
  static const maptilerKey = '01xLNZAkSsB8MUeHHQXh';

  /// 256px raster tiles, so flutter_map's default tileSize (256) renders at the
  /// correct zoom with no zoomOffset needed. `streets-v2` is a full street map.
  static const tileUrl =
      'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=$maptilerKey';

  /// Attribution required by the MapTiler and OpenStreetMap terms of use.
  /// (SimpleAttributionWidget already prefixes "© ", so no leading symbol.)
  static const attribution = 'MapTiler · OpenStreetMap contributors';
}
