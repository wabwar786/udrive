# UDrive — WhatsApp messages (admin se control)

Pichla zip (`UDrive_tour_rent_home.zip`) pehle laga hona chahiye.

## 1. Pehle delete karein
Kuch delete nahi karna.

## 2. Zip lagayein
**Kahan:** apne PC par. `files` folder ka maal repo ki root par copy karein (replace), phir GitHub Desktop se commit + push.
- Railway API khud deploy hoga; migration `078_whatsapp_templates.sql` khud chalegi.
- Admin portal khud deploy hoga.
- App mein koi badlaav nahi — nayi build ki zaroorat nahi.
- WA Engine wohi jo admin settings mein set hai (login code wala). Naya key/env nahi.

## 3. Tasdeeq (har file mein yeh search karein)
| File | | Search string |
|---|---|---|
| `udrive_api/Infrastructure/Persistence/Migrations/078_whatsapp_templates.sql` | nai | `whatsapp_outbox` |
| `udrive_api/Services/WhatsAppOutbox.cs` | nai | `public static partial class WhatsAppOutbox` |
| `udrive_api/Services/WhatsAppOutboxWorker.cs` | nai | `FOR UPDATE SKIP LOCKED` |
| `udrive_api/Services/MessageTemplateService.cs` | nai | `placeholder_unknown` |
| `udrive_api/Controllers/AdminMessageTemplatesController.cs` | nai | `api/v1/admin/message-templates` |
| `udrive_api/Models/MessageTemplateDtos.cs` | nai | `record MessageTemplateDto` |
| `admin_portal/app/message-templates/page.tsx` | nai | `Default text` |
| `udrive_api/Services/PackageMarketplaceService.cs` | badli | `QueueTourWhatsAppAsync` |
| `udrive_api/Services/RentalService.cs` | badli | `QueueRentWhatsAppAsync` |
| `udrive_api/Services/TourRentDriverService.cs` | badli | `WaitlistAcceptedCustomer` |
| `udrive_api/Services/DriverWalletService.cs` | badli | `WhatsAppOutbox.WalletLowDriver` |
| `udrive_api/Services/TeamAccess.cs` | badli | `"/api/v1/admin/message-templates"` |
| `udrive_api/Program.cs` | badli | `new WhatsAppOutboxWorker(` |
| `admin_portal/app/components/admin-frame.tsx` | badli | `'WhatsApp messages'` |
| `admin_portal/app/lib/permissions.tsx` | badli | `'/message-templates'` |

## Ab kaise chalta hai
| Kab | Kis ko |
|---|---|
| Tour booking | Customer + driver (apna apna message) |
| Rent booking (seedhi confirm) | Customer + driver |
| Rent booking jo owner ne khud accept ki (wallet kam wali) | Sirf customer |
| Waiting list accept | Sirf customer |
| Wallet had se neeche | Driver (City rides, Tour, Rent — aik hi wallet) |

- **Admin → Setup → WhatsApp messages:** har message ka text badlein, `{placeholder}` click kar ke daalein, Active/Band karein, "Default text" se wapas. Ghalat `{...}` save nahi hota.
- Har card par 7 din mein kitne gaye / fail hue.
- Message booking ke saath queue hota hai aur background se 10 second mein jata hai; fail ho to 3 dafa koshish. WhatsApp band ho to bhi booking hoti hai.
- Hotel: owners ka wallet abhi nahi, is liye hotel ka wallet message nahi.
