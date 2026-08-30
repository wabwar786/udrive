# Emergency Microphone and Customer Navigation Update

## Customer navigation
- Compact floating white pill navigation matching the supplied reference
- Four icon-only tabs: Home, Explore Kashmir, Tour Packages, Profile
- Center raised red microphone/panic button
- Selected tab uses a green indicator
- Tap microphone: starts a 3-second cancellable emergency countdown
- Long-press microphone: opens all emergency call and location-share options

## Emergency microphone behavior
The provided WA Engine API supports text messages, not audio attachments. Therefore the microphone is implemented as a discreet panic trigger:

1. Gets the customer's current GPS location
2. Creates an SOS case for Udrive Admin/Safety
3. Sends an emergency WhatsApp text with Google Maps location to all trusted WhatsApp contacts
4. Backend automatically includes the configured Udrive Safety WhatsApp number
5. Shows direct call buttons for Rescue 1122 and Police 15

## AJK emergency contacts included
- Rescue 1122
- Police 15
- AJK Tourist Helpline: 05822-924300
- AJK Tourist Helpline: 05822-921649
- Muzaffarabad Police Control: 05822-930418
- Neelum Police Control: 05821-930000
- SDMA Operations: 05822-921591

## Railway API variables
```text
WA_ENGINE_BASE_URL=https://wa-engine-deploy-production.up.railway.app/
WA_ENGINE_API_KEY=<rotated secret key>
UDRIVE_SAFETY_WHATSAPP_NUMBER=923001234567
```

Government emergency numbers are call-only. WhatsApp alerts are sent only to valid mobile WhatsApp contacts and the configured Udrive Safety number.
