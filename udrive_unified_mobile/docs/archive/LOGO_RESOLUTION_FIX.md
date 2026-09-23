# Udrive Logo Resolution Fix

This update replaces previous low-quality / stretched branding assets with your original logos.

## What was fixed
- Replaced customer app icon with the original **U** icon
- Replaced all customer/admin wordmarks with the original **Udrive** logo
- Re-generated high-resolution PNG assets for:
  - Flutter assets
  - Flutter web favicon and PWA icons
  - Android launcher icons
  - iOS app icons
  - Admin portal branding images
- Cropped transparent margins and exported cleaner versions
- Updated code to use **v3** branding asset files
- Added cache-busting through new filenames and query strings
- Improved render quality with high filter quality in Flutter image widgets
- Simplified Admin sidebar branding:
  - Expanded sidebar = full wordmark only
  - Collapsed sidebar = U icon only

## Main files updated
- `udrive_unified_mobile/assets/images/udrive_icon_v3.png`
- `udrive_unified_mobile/assets/images/udrive_wordmark_v3.png`
- `admin_portal/public/branding/udrive-icon-v3.png`
- `admin_portal/public/branding/udrive-wordmark-v3.png`

## Note
After deploy, old cached logo files should stop appearing because v3 filenames are used.
