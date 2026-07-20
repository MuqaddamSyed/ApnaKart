export interface Fix {
  lat: number;
  lng: number;
  accuracyM: number;
}

/** Browser geolocation with a hard timeout. Mirrors the app's getFix():
 *  a coarse fix (>150m) is flagged so callers can warn or reject. */
export function getFix(timeoutMs = 15000): Promise<Fix> {
  return new Promise((resolve, reject) => {
    if (!('geolocation' in navigator)) {
      reject(new Error('Location is not supported by this browser.'));
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) =>
        resolve({
          lat: pos.coords.latitude,
          lng: pos.coords.longitude,
          accuracyM: pos.coords.accuracy,
        }),
      (err) => {
        const msg =
          err.code === err.PERMISSION_DENIED
            ? 'Location permission was denied. Allow location for this site in your browser settings.'
            : err.code === err.POSITION_UNAVAILABLE
              ? 'Could not determine your location. Move to an open area and retry.'
              : 'Could not get a location fix in time. Try again.';
        reject(new Error(msg));
      },
      { enableHighAccuracy: true, timeout: timeoutMs, maximumAge: 30000 },
    );
  });
}

export const isPrecise = (f: Fix) => f.accuracyM <= 150;

export const distanceKm = (lat1: number, lng1: number, lat2: number, lng2: number) => {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
};

/** Rough ETA matching the app: ~20km/h town speed + 5 min handling. */
export const etaMinutes = (km: number) => Math.round((km / 20) * 60) + 5;
