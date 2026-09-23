# UDrive tourism carousel and inline locations update

- Replaced the live map in the customer-home hero with an automatically rotating Kashmir destination image carousel.
- Carousel changes every 3 seconds, shows destination names, and supports manual swiping.
- Added all saved Kashmir locations to the carousel, with safe image fallbacks for locations without a dedicated asset.
- Removed navigation to a separate booking window when tapping From or Where to.
- Added an inline saved-location dropdown directly inside the home ride planner.
- Tapping From or Where to smoothly scrolls the planner near the top of the viewport.
- Users can scroll back down normally at any time.
- Selecting a tourism card also fills the destination inline instead of opening another window.
- Updated customer footer to the approved dark navy/lime scheme, added compact labels, and retained the centered SOS action.
- Added compact global typography and visual density for smaller, more consistent fonts.

Primary files updated:
- `udrive_unified_mobile/lib/screens/customer/customer_home_screen.dart`
- `udrive_unified_mobile/lib/screens/main_shell.dart`
- `udrive_unified_mobile/lib/core/theme/app_theme.dart`
