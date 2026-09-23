# Customer SOS and WhatsApp Integration

## Customer navigation changes
- Customer Wallet removed from bottom navigation, drawer and customer profile shortcuts.
- Customer bottom navigation now contains:
  - Home
  - Explore
  - Round SOS button
  - Packages
  - Profile
- My Trips remains available in the customer drawer/menu.

## SOS popup
The round SOS button opens a popup containing:
- Rescue 1122
- Police 15
- Udrive Safety
- All trusted contacts saved by the customer

Each record contains:
- Direct Call button (`tel:`)
- WhatsApp location-share button where a valid mobile number exists

## WhatsApp integration
Flutter calls the Udrive API endpoint:

`POST /api/v1/communication/whatsapp/location-share`

The Udrive API then calls WA Engine. The WA Engine API key is never stored in Flutter or Admin code.

Required Railway API variables:

```text
WA_ENGINE_BASE_URL=https://wa-engine-deploy-production.up.railway.app/
WA_ENGINE_API_KEY=<ROTATED SECRET KEY>
```

Because a WA Engine key was shared in chat, rotate it before production use and store only the replacement value in Railway.
