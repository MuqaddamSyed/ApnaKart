# myMinto launcher-icon source files

Drop these two PNGs here, then run `flutter pub run flutter_launcher_icons`
from the repo root. The tool resizes everything (all Android densities, iOS
sizes, and adaptive icons) — no other tooling needed.

## Files required

### 1. `icon.png` — the standard app icon
- **1024 × 1024 px**, square, PNG.
- Content: **the monogram only** (green "m" + yellow figure). **Not** the full
  "my Minto / in Minutes" lockup — text is unreadable at icon size and hurts
  store approval.
- Background: **solid** (white `#FFFFFF` matches your logo; iOS forbids
  transparency, and `remove_alpha_ios` will flatten it anyway).
- Leave ~12–15% padding around the mark so it isn't cropped.

### 2. `icon_foreground.png` — the Android adaptive-icon foreground
- **1024 × 1024 px**, PNG, **transparent** background.
- Content: the same monogram, but **smaller** — keep it within the centre
  ~66% (Android masks the outer third into circles/squircles/etc). Roughly
  25–30% empty margin on all sides.
- The background colour is set in pubspec (`adaptive_icon_background: #FFFFFF`);
  change that hex there if you want a coloured tile instead of white.

## How to export from the logo you have
Open the full logo in any editor (Canva/Figma/Photoshop/even Preview), crop to
just the green-m + yellow-figure mark, export a square 1024×1024 twice:
one on white (`icon.png`) and one on transparent with extra margin
(`icon_foreground.png`).

## After generating
Rebuild the apps (`flutter clean` then the flavor builds) and reinstall — the
new icon shows on the home screen.
