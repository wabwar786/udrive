# Validation report

Validated before packaging:

- 27 Dart source files included
- Relative imports resolve to existing files
- Parentheses, brackets and braces are balanced across Dart sources
- Customer and Driver shells are connected through `AppController`
- Customer → Driver and Driver → Customer mode switches are present
- English and Urdu localization keys used by screens are available in both maps
- Railway Dockerfile uses Flutter stable builder and Node 20 Debian runtime
- No stale references to the previous separate app class or driver localization scope

The full Flutter compiler could not be executed in this generation environment because the Flutter SDK is not installed. The project includes a bootstrap script and is structured for Flutter 3.44/stable, matching the Railway environment used for the earlier UDrive builds.
