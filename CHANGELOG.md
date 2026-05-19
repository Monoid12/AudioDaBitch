# Changelog

## [0.4.3] - 2026-05-19

### Added
- Native SwiftUI application structure for AudioDaBitch.
- App-internal GitHub update check for `Monoid12/AudioDaBitch`.
- Update button appears only when a newer public GitHub Release exists.
- GitHub Release changelog display inside the application.
- Local changelog tab using this `CHANGELOG.md`.
- Fixed log directory: `~/Library/Logs/AudioDaBitch/`.
- Buttons for opening logs and exporting a diagnostic ZIP.
- Integrated setup guide for BlackHole 2ch, BlackHole 16ch, Discord, xPilot and AudioDaBitch routing.
- Warnings against Multi-Output direct-monitoring paths.
- xPilot automatic voice leveling to reduce extreme VATSIM volume jumps.
- Fast xPilot peak guard before the master limiter.
- Local HTTP control API for Stream Deck integration.
- Stream Deck plugin scaffold for Stream Deck XL button actions and Stream Deck + dial actions.
- GitHub Actions workflow that builds an unsigned `.pkg` and attaches it to a GitHub Release.
- `push_to_github.command` for local authenticated push via GitHub CLI.

### Changed
- Removed AppleScript launcher usage to avoid the previous quoting/startup error.
- Removed Tkinter/PyObjC GUI dependency from the user-facing app.
- Normal app start no longer requires `.command` files and should not open Terminal.

### Known limitations
- The first release remains unsigned because no Apple Developer ID is available yet.
- The audio engine uses a bundled Python helper process that is started silently by the native SwiftUI app.
- BlackHole routing is required because macOS does not expose app output as separate inputs by default.
- Stream Deck plugin is a first scaffold and should be tested with Elgato's tooling before public distribution.

## [0.4.1] - 2026-05-19

### Added
- Hotfix package with cleanup for old GamingAudioLimiter folders.
- Diagnostic command.

### Fixed
- Removed old GamingAudioLimiter app remnants during install.

## [0.4.0] - 2026-05-19

### Added
- First AudioDaBitch-branded prototype.
- Native-style GUI attempt.
- App icon.
- About text: `Made with ♥ in Berlin - by Michel Damhorst`.
