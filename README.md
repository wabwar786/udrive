# Driver Offer pickupAt Build Hotfix

Replace:
`udrive_api/Services/BookingService.cs`

Fixes CS0103 by declaring `pickupAt` outside the lock-command scope so it remains available when setting the Driver offer expiry.
