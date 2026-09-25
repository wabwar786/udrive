# UDrive brand assets

Everything that draws the UDrive identity reads from this folder. Replacing
the logo is a matter of replacing these files — no Dart change, no hunting
through widgets.

| file | used by |
| --- | --- |
| `app_icon_1024.png` | the launcher icon on Android and iOS, and the Play Store icon |
| `android_adaptive_foreground_1024.png` | the lime pin layer of the Android 8+ adaptive icon |
| `android_monochrome_1024.png` | the Android 13+ themed icon |
| `playstore_icon_512.png` | `play_store/graphics/01_app_icon_512.png` |
| `splash_logo_1152.png` | the launch window the OS paints before Flutter starts |
| `udrive_logo_stacked_light.png` | `lib/screens/splash_screen.dart` |
| `udrive_logo_horizontal_light.png` / `_dark.png` | `UDriveWordmark` in `lib/core/widgets/brand.dart` |
| `udrive_mark_navy_1024.png` / `_lime` / `_white` | `UDriveMark`, by `UDriveMarkTone` |

Navy on light, lime on dark, white where neither works. Lime is a *surface*
and never carries white text — see the contrast note at the top of
`lib/core/theme/app_theme.dart`.

## Regenerating the platform icons

The Android mipmaps and drawables, the iOS AppIcon set and launch images, and
the web icons are all generated from the four source files above:

```
python3 tool/gen_brand_assets.py
```

run from the root of `udrive_unified_mobile`. It reads only the four source
files in this folder, needs Pillow (`pip install pillow`), and writes 49 files —
every Android mipmap and drawable, the iOS AppIcon set and launch images, the
web icons, and the Play Store icon — printing each one.

This is deliberately a script rather than `flutter_launcher_icons` /
`flutter_native_splash`: those are two more dev dependencies to resolve on
every CI run, and they cannot produce the density-bucketed pre-Android-12
splash bitmap this app uses. If you would rather use them, the kit's
`README.txt` carries the `pubspec.yaml` block.

After regenerating, bump `versionCode` before the next Play upload — Play
rejects a build whose code has not increased.
