# AudioDaBitch Changelog

## 0.5.17 - Compact UI and Clear Update Badge

* VU needle pivots now sit between the VU label and the live dB readout.
* The crowded -10 label was removed while its scale tick remains, so -6 and 0 stay readable.
* The main window is narrower and lower with less empty space around the three VU blocks.
* The Leveling page scrolls below Response speed, keeping the main leveling controls usable in the shorter window.
* Automatic update checks now retry after launch and refresh the visible Updates tab badge without opening the Updates tab.

## 0.5.16 - VU Readability and Auto Start

* VU tick marks and scale labels now sit higher inside the beige meter face.
* VU needles are longer but remain inside the meter window.
* Discord, xPilot and Output labels stay centered and readable while only the needle moves across them.
* Saved Discord, xPilot and Output devices are restored automatically on startup.
* Audio starts automatically after launch/update when all three saved devices are available.
* Audio engine processing remains unchanged apart from the version bump.

## 0.5.15 - VU Needle Containment

* VU needles now use a shorter, inset path so they never extend beyond the beige meter face.
* VU ticks and labels use a safer internal drawing area.
* Audio engine behavior remains unchanged apart from the version bump.

## 0.5.14 - VU Face Geometry Fix

* VU scale labels now stay inside the beige meter face.
* VU needles now pivot and move inside the beige meter face.
* Live dB readouts are shown inside the meter face.
* Audio engine behavior remains unchanged apart from the version bump.

## 0.5.13 - Analog VU and Rotary Controls

* Discord, xPilot and Output now use native analog VU meters.
* Audio, leveling and ducking controls now use lightweight rotary knobs.
* Knobs can be adjusted by dragging with the mouse.
* Knobs also react to the scroll wheel while the pointer is over them.
* The audio engine remains unchanged apart from the version bump.

## 0.5.12 - Automatic Updates and Device Restore

* Update checks run automatically on launch and retry if GitHub is not reachable immediately.
* Device refresh retries while the engine is still starting, so the list appears without pressing Refresh Devices.
* Saved Discord, xPilot and Output devices are restored into the UI on startup.
* Device names are stored together with IDs, so AudioDaBitch can recover if macOS changes device IDs.
* Saved volume, pan, leveling and ducking controls are restored automatically.

## 0.5.11 - Ducking, Latency and Performance

* xPilot-priority ducking now reacts much faster, so Discord is reduced as soon as ATC audio appears.
* New Ducking controls are visible in the Leveling tab:
  - Trigger threshold
  - Discord reduction
  - Attack
  - Release
* The engine trims oversized input queues to prevent delayed xPilot audio.
* Python callback overhead is lower thanks to chunked audio buffers and a lighter output mixer.
* Discord and xPilot automatic leveling now use RMS-based speech detection for steadier correction.
* Main diagnostics show Discord/xPilot queue time and dropped-buffer time.
* Updates, Changelog and Help use styled headings, color and symbols inside the app.

## 0.5.10 - English UI and Dual Channel Leveling
* All visible app labels, buttons, status messages and in-app documents are now English.
* Discord channel 1 now has the same automatic leveling logic as xPilot channel 2.
* The Leveling tab now exposes controls for both channels:
  - Enable leveling
  - Target loudness
  - Maximum boost
  - Maximum cut
  - Response speed
* The Updates, Changelog and Help tabs were rewritten with clearer headings and symbols.

## 0.5.9 - Installer Fix
* The PKG installs AudioDaBitch.app reliably into /Applications.
* macOS PackageKit is prevented from relocating the app to old local build folders.
* The audio engine remains on the stable 0.5.8 / 0.5.6 audio base.

## 0.5.8 - Restore / Update / Release Fix
* Restored the stable 0.5.6 audio base.
* Bootstraps sounddevice 0.5.5 and cffi reliably.
* /shutdown now stops the engine cleanly and removes the PID file.
* The Updates tab checks GitHub releases from Monoid12/AudioDaBitch.
* New releases show a blue update badge and enable the Install Update button.
* Updates download AudioDaBitch.pkg, stop the engine, open the installer and restart the app.
* PKG build and postinstall checks verify /Applications/AudioDaBitch.app.
* Changelog and Help stay visible and populated.

## 0.5.6 - Stable Audio Base
* Stable 48 kHz safe mode with a larger buffer and high latency by default.
* Ring buffers between input and output streams reduce short timing glitches.
* Main window diagnostics show sample rate, block size, latency and callback errors.
* Stabilize Audio resets safe audio parameters and restarts audio.
* Changelog, Help and Log ZIP are available inside the app.
