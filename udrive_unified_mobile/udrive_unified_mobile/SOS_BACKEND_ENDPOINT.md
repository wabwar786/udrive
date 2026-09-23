# Emergency voice broadcast API required

The Flutter client now calls:

`POST /api/v1/communication/whatsapp/emergency-voice-broadcast`

Content type: `multipart/form-data`

Fields:
- `audio`: PCM 16-bit mono, 16 kHz recording
- `numbers`: comma-separated personal emergency contact numbers
- `latitude`
- `longitude`
- `accuracyMeters`
- `customerName`

Expected success response:

```json
{
  "success": true,
  "data": {
    "recipientCount": 2
  }
}
```

The API should:
1. Store the emergency recording securely.
2. Create an SOS/audit record.
3. Convert PCM to a WhatsApp-supported audio format when required.
4. Send the audio and map location to personal contacts through the configured WhatsApp API.
5. Notify Udrive safety operations.
6. Never attempt to send recordings to official call-only numbers such as 15 or 1122.
