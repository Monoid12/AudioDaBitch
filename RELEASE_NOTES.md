# AudioDaBitch 0.5.12

Automatic update checks and reliable device restore.

- GitHub update checks now run automatically on launch and retry if GitHub is slow or unreachable at first.
- The device list refreshes automatically while the engine is still starting.
- Saved Discord, xPilot and Output devices are restored into the UI on startup.
- Device names are stored together with device IDs, so AudioDaBitch can recover if macOS changes IDs.
- Saved volume, pan, leveling and ducking controls are restored before any manual Refresh Devices step.
- The 0.5.11 ducking, latency and leveling improvements remain in place.
