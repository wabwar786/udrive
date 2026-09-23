# Explore Kashmir — Data and Package Flow

## Destinations
Explore Kashmir destinations are managed from:

`Admin Portal → Tourism → Destinations`

Admin can add/edit:
- Destination name
- District
- Summary
- Cover image URL
- Best season
- Recommended vehicle
- Network status
- Route safety score
- Active/inactive status

Only active destinations returned by `/api/v1/catalog/destinations` appear in Customer → Explore Kashmir → Destinations.

## Driver Packages
Driver flow:

`Driver Mode → Packages → Create live tour package → Submit for approval`

Admin flow:

`Admin Portal → Tour Packages / Tourism Marketplace → Review → Approve`

After approval and activation, the package appears in:
- Customer → Explore Kashmir → Driver Packages
- Customer → Tour Packages / Join Tour listings
- Customer home package/vehicle recommendations where applicable

Draft, pending, rejected, paused or inactive packages do not appear publicly.
