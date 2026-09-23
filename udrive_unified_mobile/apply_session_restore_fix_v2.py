from pathlib import Path
import re
import shutil

repo = Path(__file__).resolve().parent

controller_path = (
    repo
    / "udrive_unified_mobile"
    / "lib"
    / "core"
    / "state"
    / "app_controller.dart"
)

session_target = (
    repo
    / "udrive_unified_mobile"
    / "lib"
    / "core"
    / "auth"
    / "session_store.dart"
)

session_source = repo / "patch_payload" / "session_store.dart"
pubspec_path = repo / "udrive_unified_mobile" / "pubspec.yaml"

if not controller_path.exists():
    raise SystemExit(
        f"Missing file: {controller_path}\n"
        "Extract this ZIP into the ROOT of the udrive repository."
    )

if not session_source.exists():
    raise SystemExit(f"Missing patch payload: {session_source}")

text = controller_path.read_text(encoding="utf-8")

initialize_pattern = re.compile(
    r"Future(?:\s*<\s*void\s*>)?\s+initialize\s*"
    r"\(\s*\)\s*async\s*\{",
    re.MULTILINE,
)

request_pattern = re.compile(
    r"Future(?:\s*<[^>]+>)?\s+requestOtp\s*\(",
    re.MULTILINE,
)

initialize_match = initialize_pattern.search(text)
if initialize_match is None:
    position = text.find("initialize")
    context = text[max(0, position - 120):position + 240]
    raise SystemExit(
        "Could not locate the initialize() method.\n"
        f"Nearby source:\n{context}"
    )

request_match = request_pattern.search(text, initialize_match.end())
if request_match is None:
    position = text.find("requestOtp")
    context = text[max(0, position - 120):position + 240]
    raise SystemExit(
        "Could not locate the requestOtp() method.\n"
        f"Nearby source:\n{context}"
    )

if "import 'dart:async';" not in text:
    text = "import 'dart:async';\n" + text

initialize_match = initialize_pattern.search(text)
request_match = request_pattern.search(text, initialize_match.end())

replacement = '''Future<void> initialize() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));

      _locale = Locale(prefs.getString('language') ?? 'en');
      _mode = (prefs.getString('mode') ?? 'customer') == 'driver'
          ? UserMode.driver
          : UserMode.customer;
      _driverOnline = prefs.getBool('driverOnline') ?? true;
      _liveTrip.shareEnabled =
          prefs.getBool('liveShareEnabled') ?? false;

      _currentUser = await _sessionStore.readUser();

      final accessToken = await _sessionStore.readAccessToken();
      final refreshToken = await _sessionStore.readRefreshToken();
      final accessExpiry = await _sessionStore.readAccessExpiry();

      final accessTokenIsUsable =
          _currentUser != null &&
          accessToken != null &&
          accessToken.isNotEmpty &&
          accessExpiry != null &&
          accessExpiry.isAfter(
            DateTime.now().add(const Duration(seconds: 30)),
          );

      if (accessTokenIsUsable) {
        _loggedIn = true;
        _initialized = true;
        notifyListeners();

        unawaited(_validateCachedSession());
        return;
      }

      final hasStoredSession =
          (accessToken != null && accessToken.isNotEmpty) ||
          (refreshToken != null && refreshToken.isNotEmpty);

      if (hasStoredSession) {
        try {
          _currentUser = await _authRepository
              .me()
              .timeout(const Duration(seconds: 15));
          _loggedIn = true;

          await _loadDriverState()
              .timeout(const Duration(seconds: 10));
        } catch (_) {
          await _resetSessionSafely();
        }
      } else {
        _loggedIn = false;
        _currentUser = null;
        _mode = UserMode.customer;
      }
    } catch (_) {
      await _resetSessionSafely();
    } finally {
      if (!_initialized) {
        _initialized = true;
        notifyListeners();
      }
    }
  }

  Future<void> _validateCachedSession() async {
    try {
      _currentUser = await _authRepository
          .me()
          .timeout(const Duration(seconds: 15));

      await _loadDriverState()
          .timeout(const Duration(seconds: 10));

      _authError = null;
    } on TimeoutException {
      // Keep the valid cached account available in slow/offline mode.
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _resetSessionSafely();
      }
    } catch (_) {
      // Temporary network/storage errors must not cause endless splash.
    } finally {
      notifyListeners();
    }
  }

  Future<void> _resetSessionSafely() async {
    try {
      await _sessionStore
          .clear()
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      // Continue to Login even if secure storage cleanup fails.
    }

    _currentUser = null;
    _driverProfile = null;
    _liveVehicles = const [];
    _loggedIn = false;
    _mode = UserMode.customer;
  }

  '''

updated = (
    text[:initialize_match.start()]
    + replacement
    + text[request_match.start():]
)

required_tokens = [
    "import 'dart:async';",
    "Future<void> initialize() async",
    "unawaited(_validateCachedSession())",
    "Future<void> _validateCachedSession() async",
    "Future<void> _resetSessionSafely() async",
]

missing = [token for token in required_tokens if token not in updated]
if missing:
    raise SystemExit(f"Patch validation failed. Missing: {missing}")

if not request_pattern.search(updated):
    raise SystemExit("Patch validation failed: requestOtp() was lost.")

if updated.count("Future<void> initialize() async") != 1:
    raise SystemExit(
        "Patch validation failed: initialize() was duplicated."
    )

controller_path.write_text(updated, encoding="utf-8")
session_target.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(session_source, session_target)

if pubspec_path.exists():
    pubspec = pubspec_path.read_text(encoding="utf-8")
    version_match = re.search(
        r"^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$",
        pubspec,
        flags=re.MULTILINE,
    )

    if version_match:
        major, minor, patch, build = map(int, version_match.groups())
        new_version = f"version: {major}.{minor}.{patch + 1}+{build + 1}"
        pubspec = (
            pubspec[:version_match.start()]
            + new_version
            + pubspec[version_match.end():]
        )
        pubspec_path.write_text(pubspec, encoding="utf-8")
        print(f"Updated {new_version}")

print("Updated app_controller.dart")
print("Updated session_store.dart")
print("Robust session restore patch validation passed.")
