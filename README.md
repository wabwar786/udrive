# UDrive — Cleanup (sirf delete, koi file badli nahi)

**704 files** hatai jati hain jo live software mein use nahi hotin. Koi code file
**edit nahi** hui, koi nayi file repo mein nahi aati.

## Chalane ka tareeqa

**Kahan:** apne PC par, **repo ki root folder** mein (jahan `udrive_api`,
`admin_portal`, `udrive_unified_mobile` folders hain).

1. `cleanup_udrive.ps1` ko repo ki root folder mein copy karein.
2. Usi folder mein PowerShell kholein (folder mein Shift + Right-click → "Open PowerShell window here") aur chalayein:

   ```
   powershell -ExecutionPolicy Bypass -File .\cleanup_udrive.ps1
   ```
3. Aakhir mein likha aayega: `Delete hue: ...`
4. `cleanup_udrive.ps1` ko repo se **hata dein** (commit nahi karni).
5. GitHub Desktop → commit → push.

Script khud check karti hai ke aap root folder mein hain — ghalat jagah chali to kuch delete nahi karti.

## Kya delete hota hai

| Hissa | Files |
|---|---|
| `udrive_unified_mobile/udrive_api/` — purani duplicate copy | 203 |
| `udrive_unified_mobile/admin_portal/` — purani duplicate copy | 66 |
| `udrive_unified_mobile/docs/`, `play_store/`, `.github/`, `scripts/`, `testing/`, khali `udrive_unified_mobile/` | 137 |
| Root `docs/`, `patch_payload/`, `scripts/`, `testing/` | 112 |
| Dart files jo `main.dart` se kabhi compile nahi hotin | 16 |
| `web/` ke purane favicon/icon (v1–v3) | 15 |
| `admin_portal/public/branding/` ki 4 purani images | 4 |
| Root aur mobile ke purane notes, `apply_*` scripts, `.bat.txt` copies, PDF | 151 |

Poori list `cleanup_udrive.ps1` ke andar hai.

## Jo rakha gaya

- Root: `README.md`, `UDrive_Admin_Guide.md`, `UDrive_Customer_Guide.md`, `UDrive_Driver_Guide.md`, `API_ENDPOINTS.md`, `DATABASE_CHANGES.md`, `play_store/`, `.github/`
- Mobile: `create_upload_key.bat/.sh`, `build_play_bundle.bat`, `build_apk_windows.bat`, `build_apk.sh` (+ inke `BUILD_APK.md`, `WINDOWS_SCRIPTS_README.txt`)
- `lib/core/widgets/driver_location_coordinator.dart` — `analysis_options.yaml` ki exclude list mein hai **magar live hai** (`main_shell.dart` use karta hai). Nahi hataya.

## Tasdeeq (verify)

**GitHub Desktop mein:** sirf **Deleted** files nazar aayen, **Modified 0**, **Added 0**.

Yeh files **mojood nahi** honi chahiye:

| File / folder | Hona chahiye |
|---|---|
| `udrive_unified_mobile/udrive_api` | gayab |
| `udrive_unified_mobile/admin_portal` | gayab |
| `udrive_unified_mobile/lib/models/models.dart` | gayab |
| `udrive_unified_mobile/lib/screens/home/home_screen.dart` | gayab |
| `udrive_unified_mobile/web/favicon.png` | gayab |

Yeh files **mojood** rehni chahiye:

| File | Search string |
|---|---|
| `udrive_unified_mobile/lib/screens/customer/driver_offers_screen.dart` | `class DriverOffersScreen` |
| `udrive_unified_mobile/lib/core/widgets/driver_location_coordinator.dart` | `DriverLocationCoordinator` |
| `udrive_unified_mobile/web/favicon-v4.png` | (file mojood) |
| `admin_portal/public/branding/udrive-icon-v3.png` | (file mojood) |

**Kahan: GitHub → Actions → Build UDrive → Run workflow** — push ke baad
**Analyze** job hara (green) hona chahiye.

## Static checks (cleanup ke baad)

| Check | Pehle | Ab |
|---|---|---|
| audit_structure | CLEAN | CLEAN |
| check_imports — missing imports | 1 (jhoota) | **0** |
| check_imports — orphaned files | 9 | **0** |
| check_imports — missing awaits | 4 | 4 |
| check_required_args | 10 | **1** (`safety_repository.dart` ka apna local `TrustedContact` — jhoota alarm) |
| check_const_colours | 0 | 0 |
| Dart reachability | 157 / 173 | **157 / 157** |
| Admin portal unused modules | 0 | 0 |
