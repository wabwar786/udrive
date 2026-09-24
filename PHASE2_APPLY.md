# Phase 2 — brand kit. How to apply.

This drop also carries the Part 2 files (rev 143) that were never placed, so
there is nothing separate to apply first. Build label goes to **rev 144**.

## 1. Copy

Extract over `D:\Softwares\Github\uDrive\`, keeping the folder structure.
Both `udrive_unified_mobile\` and `play_store\` sit at that level. Say yes to
replacing existing files.

Check afterwards that the files landed in the real tree and not in a nested
`udrive_unified_mobile\udrive_unified_mobile\`.

## 2. Delete the files the brand replaces

These are the previous logo and the old web icons. Nothing references them any
more and they would otherwise keep shipping inside every build. In PowerShell,
from `D:\Softwares\Github\uDrive\udrive_unified_mobile`:

```powershell
Remove-Item -Force -ErrorAction SilentlyContinue `
  assets\images\udrive_icon.png, assets\images\udrive_icon_v2.png, `
  assets\images\udrive_icon_v3.png, assets\images\udrive_mark.png, `
  assets\images\udrive_wordmark.png, assets\images\udrive_wordmark_v2.png, `
  assets\images\udrive_wordmark_v3.png, `
  lib\core\theme\accent_store.dart, `
  android\app\src\main\res\drawable\launch_icon.png, `
  web\favicon.png, web\favicon-v2.png, web\favicon-v3.png, `
  web\icons\Icon-192.png, web\icons\Icon-192-v2.png, web\icons\Icon-192-v3.png, `
  web\icons\Icon-512.png, web\icons\Icon-512-v2.png, web\icons\Icon-512-v3.png, `
  web\icons\Icon-maskable-192.png, web\icons\Icon-maskable-192-v2.png, `
  web\icons\Icon-maskable-192-v3.png, web\icons\Icon-maskable-512.png, `
  web\icons\Icon-maskable-512-v2.png, web\icons\Icon-maskable-512-v3.png
```

`launch_icon.png` matters: it has moved into `drawable-mdpi` … `drawable-xxxhdpi`.
Leaving the old unqualified copy behind makes Android draw it at four times its
size on a high-density phone.

`accent_store.dart` matters too — the colour picker is gone, and the file no
longer compiles against the new theme.

## 3. Bump versionCode, then push

`android/app/build.gradle.kts` — Play rejects an upload whose `versionCode`
has not increased since the last one.

## 4. What to look at in the build

- The launcher icon, and the icon under Settings → Apps (navy tile, lime pin).
- Cold start: white launch window with the navy pin, then the splash with
  "UDrive / DISCOVER KASHMIR" and the mountains. No green flash at any point.
- Any loading spinner — every one of them was invisible before this drop.
- The ride booking sheet ("Confirm your ride"): every label on it was white on
  white until now.
- Trip chat, your own messages.

## 5. Still to do by hand

`play_store/graphics/03_phone_screenshot_*.png` are captures of the previous
green build. They need recapturing from this build before the store listing
goes live — `play_store/_source_for_regeneration/render.js` frames them once
you drop new captures into `s1_home.png` … `s5_offer.png`.
