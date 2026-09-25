#!/usr/bin/env python3
"""Generate every platform icon and splash asset from the UDrive brand kit.

Sources, all of them checked in under assets/brand/ and none redrawn here:
  app_icon_1024.png                    navy field, lime pin   -> launcher / iOS
  android_adaptive_foreground_1024.png pin alone, safe-zoned  -> adaptive fg
  android_monochrome_1024.png          pin alone, flat        -> themed icon
  splash_logo_1152.png                 navy pin, transparent  -> splash

Usage, from the root of udrive_unified_mobile:

    python3 tool/gen_brand_assets.py

Needs Pillow (pip install pillow). Writes 48 files and prints every one.
"""
import os
import sys
from PIL import Image, ImageDraw

APP = sys.argv[1] if len(sys.argv) > 1 else "."
KIT = os.path.join(APP, "assets/brand")

NAVY = (11, 27, 51, 255)
WHITE = (255, 255, 255, 255)

src_icon = Image.open(os.path.join(KIT, "app_icon_1024.png")).convert("RGBA")
src_fg = Image.open(os.path.join(KIT, "android_adaptive_foreground_1024.png")).convert("RGBA")
src_mono = Image.open(os.path.join(KIT, "android_monochrome_1024.png")).convert("RGBA")
src_splash = Image.open(os.path.join(KIT, "splash_logo_1152.png")).convert("RGBA")

# The kit's splash logo is a 1152 square with the pin occupying about a third of
# it. Android 12+ wants exactly that padding - it composes the icon into a 288dp
# window and shows the inner 192dp - but a layer-list <bitmap> and an iOS
# imageView draw what they are given, so those two get the pin alone.
src_pin = src_splash.crop(src_splash.split()[3].getbbox())
PIN_RATIO = src_pin.size[0] / src_pin.size[1]


def pin_at(height_px):
    return src_pin.resize((int(round(height_px * PIN_RATIO)), height_px), Image.LANCZOS)

written = []


def save(img, rel, rgb=False):
    path = os.path.join(APP, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if rgb:
        flat = Image.new("RGB", img.size, NAVY[:3])
        flat.paste(img, mask=img.split()[3] if img.mode == "RGBA" else None)
        flat.save(path, "PNG", optimize=True)
    else:
        img.save(path, "PNG", optimize=True)
    written.append(rel)


def fit(img, size):
    return img.resize((size, size), Image.LANCZOS)


def circle_mask(img):
    out = img.copy()
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, img.size[0] - 1, img.size[1] - 1), fill=255)
    out.putalpha(mask)
    return out


# --------------------------------------------------------------- Android
# Legacy launcher icon, 48dp across the density buckets.
BUCKETS = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

for name, scale in BUCKETS.items():
    px = int(round(48 * scale))
    square = fit(src_icon, px)
    save(square, f"android/app/src/main/res/mipmap-{name}/ic_launcher.png")
    save(circle_mask(square), f"android/app/src/main/res/mipmap-{name}/ic_launcher_round.png")

    # Adaptive icon layers are 108dp; the system shows the middle 72dp and
    # animates within the rest, so the pin must stay inside that safe zone —
    # which is exactly how the kit's foreground is drawn.
    apx = int(round(108 * scale))
    save(fit(src_fg, apx), f"android/app/src/main/res/drawable-{name}/ic_launcher_foreground.png")
    save(fit(src_mono, apx), f"android/app/src/main/res/drawable-{name}/ic_launcher_monochrome.png")

    # Pre-Android-12 splash bitmap. A <bitmap> in a layer-list is drawn at its
    # own pixel size, so one file per density is what keeps the pin the same
    # physical size on every phone. 96dp tall.
    save(
        pin_at(int(round(96 * scale))),
        f"android/app/src/main/res/drawable-{name}/launch_icon.png",
    )

# Android 12+ draws the splash icon itself, scaled into a 288dp window whose
# inner 192dp is visible. Its own resource name, not a density-less copy of
# launch_icon: two drawables under one name, one of them unqualified, is how a
# bitmap ends up drawn at 4x on a high-density phone.
save(fit(src_splash, 960), "android/app/src/main/res/drawable/splash_icon.png")

# --------------------------------------------------------------------- iOS
IOS = [
    ("Icon-App-20x20@1x.png", 20), ("Icon-App-20x20@2x.png", 40),
    ("Icon-App-20x20@3x.png", 60), ("Icon-App-29x29@1x.png", 29),
    ("Icon-App-29x29@2x.png", 58), ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@2x.png", 80), ("Icon-App-40x40@3x.png", 120),
    ("Icon-App-60x60@2x.png", 120), ("Icon-App-60x60@3x.png", 180),
    ("Icon-App-76x76@1x.png", 76), ("Icon-App-76x76@2x.png", 152),
    ("Icon-App-83.5x83.5@2x.png", 167), ("Icon-App-1024x1024@1x.png", 1024),
]
for name, px in IOS:
    # iOS rejects an alpha channel on app icons.
    save(fit(src_icon, px), f"ios/Runner/Assets.xcassets/AppIcon.appiconset/{name}", rgb=True)

# iOS launch image: the pin on white, matching the Flutter splash behind it.
launch_1x = None
for suffix, scale in (("", 1), ("@2x", 2), ("@3x", 3)):
    pin = pin_at(96 * scale)
    if launch_1x is None:
        launch_1x = pin.size
    save(pin, f"ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png")
print(f"LaunchImage 1x is {launch_1x[0]}x{launch_1x[1]} "
      f"- put these in the storyboard's <image name=\"LaunchImage\"> hint")

# --------------------------------------------------------------------- web
# v4 so a browser holding a cached v3 under the same name cannot win.
for px in (192, 512):
    save(fit(src_icon, px), f"web/icons/Icon-{px}-v4.png")
    # Maskable: navy bleeding to every edge, with the kit's safe-zoned pin —
    # the same layer Android's adaptive icon uses — laid over it, so a circular
    # or squircle crop takes only navy.
    field = Image.new("RGBA", (px, px), NAVY)
    field.alpha_composite(fit(src_fg, px))
    save(field, f"web/icons/Icon-maskable-{px}-v4.png")

save(fit(src_icon, 32), "web/favicon-v4.png")

# The Play Store icon is the same art at 512, and lives outside this tree.
play = os.path.join(APP, "../play_store/graphics/01_app_icon_512.png")
if os.path.isdir(os.path.dirname(play)):
    fit(src_icon, 512).convert("RGB").save(play, "PNG", optimize=True)
    written.append("../play_store/graphics/01_app_icon_512.png")

print(f"{len(written)} files")
for rel in written:
    print("  " + rel)
