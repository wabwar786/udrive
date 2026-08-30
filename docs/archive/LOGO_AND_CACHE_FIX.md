# Udrive Logo and Cache Fix

## Root cause
The previous branding package accidentally contained screenshots as logo files. This caused the customer login and Admin sidebar to render tiny screenshots inside logo containers.

## Fixed
- Replaced screenshot assets with the actual supplied Udrive wordmark and U icon.
- Cropped excess whitespace from both images.
- App icon uses only the U icon.
- Customer app displays the full Udrive wordmark.
- Admin login/sidebar/marketplace use the full wordmark without duplicate icon placement.
- Collapsed Admin sidebar uses only the U icon.
- Added versioned branding filenames (`v2`) to bypass old browser caches.
- Added no-cache headers for Admin branding files.
- Added no-cache rules for Flutter branding assets, manifest and PWA icons.
- Added one-time Flutter web cache cleanup for release `udrive-20260730-v2`.

## Deploy
Redeploy both:
1. Admin portal
2. Flutter web/customer app

After deployment the new asset names automatically bypass previous cached logo files.
