# Explore Kashmir Admin Management

## Customer app correction
The customer bottom-navigation **Explore** page now opens `LiveExploreScreen` instead of the old dummy `ExploreScreen`.

This was the reason the previous UI appeared unchanged.

## Admin workflow
Open:

`Admin Portal → Tourism → Destinations`

Admin can now:
- Add a destination
- Upload JPG, PNG or WebP cover image
- Enter English and Urdu name/description
- Edit destination details
- Publish or hide destination
- Delete an unused destination
- Search the destination catalogue

A destination linked to a route or Driver package cannot be hard-deleted. It can be hidden/deactivated so historical records stay safe.

## Customer visibility
Only active destinations appear in:

`Customer Mode → Explore Kashmir → Destinations`

## Driver packages
Driver packages appear in:

`Customer Mode → Explore Kashmir → Driver Packages`

only after Admin approval and activation.

## Image storage
Uploaded images are saved through API storage under the configured `UPLOAD_ROOT` volume and served through a public catalogue image endpoint.
