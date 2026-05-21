# Changelog

## 0.5.13

- Added native analog VU meters for Discord, xPilot and Output.
- Replaced audio, leveling and ducking sliders with lightweight native rotary knobs.
- Knobs support mouse dragging and scroll-wheel adjustment while hovered.
- Enlarged the main window so the analog controls stay readable.
- Kept the audio engine path unchanged apart from the version bump.

## 0.5.12

- Update checks now run automatically on launch and retry if GitHub is not reachable immediately.
- Device lists refresh automatically while the engine is still starting.
- Saved Discord, xPilot and Output selections are restored into the UI on startup.
- AudioDaBitch now stores device names as well as device IDs, so devices can be found again if macOS changes IDs.
- Saved volume, pan, leveling and ducking controls are restored before the user has to touch Refresh Devices.

## 0.5.11

- Tightened xPilot-priority ducking so Discord drops immediately when ATC audio appears.
- Added visible ducking controls for trigger threshold, Discord reduction, attack and release.
- Added low-latency buffer trimming to prevent queued xPilot audio from drifting late.
- Reduced Python callback overhead with chunked audio buffers and a lighter output mixer.
- Improved Discord and xPilot automatic leveling with RMS-based detection and faster correction.
- Added queue and dropped-buffer diagnostics to make latency visible in the main window.
- Made Updates, Changelog and Help more colorful with styled headings and symbols.

## 0.5.10

- Converted all visible app labels, buttons, status messages and in-app documents to English.
- Added Discord channel 1 automatic leveling using the same engine path as xPilot channel 2.
- Added visible Leveling controls for Discord and xPilot: enable, target loudness, maximum boost, maximum cut and response speed.
- Rewrote Updates, Changelog and Help content with clearer headings and symbols.

## 0.5.9

- Fixed PKG installation so `AudioDaBitch.app` is not relocated to old local build paths.
- PKG build sets `BundleIsRelocatable=false` and `BundleHasStrictIdentifier=true` for the app bundle.
- Audio base from 0.5.8 remains unchanged: stable 0.5.6 mixer with `sounddevice==0.5.5`.

## 0.5.8

- Restored the stable 0.5.6 audio base: same mixer, same panning, same safe mode, and `sounddevice==0.5.5`.
- Fixed engine shutdown so `/shutdown` exits cleanly and stale engine processes are removed.
- Added in-app updates: GitHub release check, blue update badge, `AudioDaBitch.pkg` download, engine stop, installer start and app restart.
- Hardened PKG build and `postinstall` checks for `/Applications/AudioDaBitch.app`.
- Changelog and Help tabs stay visible and populated.
- Removed the experimental Developer Tool; releases use `release.command` and `dev_check.command`.

## 0.5.6

- Stabilized audio with 48 kHz safe mode, larger buffers and ring buffers for short timing glitches.
- Fixed device selection: inputs and outputs load from the engine device list and are stored by device ID.
- Discord panning, xPilot panning, ducking, limiting and xPilot auto-leveling are visible.
- Added in-app Changelog and Help / BlackHole routing content.
- Restored app icon and Log ZIP export.
