AudioDaBitch Changelog
=====================

0.5.10 - English UI and Dual Channel Leveling
---------------------------------------------
* All visible app labels, buttons, status messages and in-app documents are now English.
* Discord channel 1 now has the same automatic leveling logic as xPilot channel 2.
* The Leveling tab now exposes controls for both channels:
  - Enable leveling
  - Target loudness
  - Maximum boost
  - Maximum cut
  - Response speed
* The Updates, Changelog and Help tabs were rewritten with clearer headings and symbols.

0.5.9 - Installer Fix
---------------------
* The PKG installs AudioDaBitch.app reliably into /Applications.
* macOS PackageKit is prevented from relocating the app to old local build folders.
* The audio engine remains on the stable 0.5.8 / 0.5.6 audio base.

0.5.8 - Restore / Update / Release Fix
--------------------------------------
* Restored the stable 0.5.6 audio base.
* Bootstraps sounddevice 0.5.5 and cffi reliably.
* /shutdown now stops the engine cleanly and removes the PID file.
* The Updates tab checks GitHub releases from Monoid12/AudioDaBitch.
* New releases show a blue update badge and enable the Install Update button.
* Updates download AudioDaBitch.pkg, stop the engine, open the installer and restart the app.
* PKG build and postinstall checks verify /Applications/AudioDaBitch.app.
* Changelog and Help stay visible and populated.

0.5.6 - Stable Audio Base
-------------------------
* Stable 48 kHz safe mode with a larger buffer and high latency by default.
* Ring buffers between input and output streams reduce short timing glitches.
* Main window diagnostics show sample rate, block size, latency and callback errors.
* Stabilize Audio resets safe audio parameters and restarts audio.
* Changelog, Help and Log ZIP are available inside the app.
