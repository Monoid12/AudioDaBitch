# AudioDaBitch

AudioDaBitch is a macOS audio routing, ducking and limiting tool for Discord + xPilot.

- Native SwiftUI GUI.
- Two app audio inputs: Discord and xPilot.
- One stereo output.
- Per-source gain and pan.
- xPilot fast auto-leveling for strongly mismatched VATSIM voice levels.
- Ducking: xPilot can duck Discord or Discord can duck xPilot.
- Master output limiter.
- GitHub update check.
- Changelog display in the app.
- Stream Deck local control API + plugin scaffold.
- Logs: `~/Library/Logs/AudioDaBitch/`.

## Current release

Version: `0.4.2`

## macOS routing concept

Everything goes into BlackHole first, then AudioDaBitch, then to the headphones.

Do not use Multi-Output devices that also include your headphones, otherwise you will hear an unprocessed direct path and the limiter cannot fully protect the signal.

See `Resources/SetupGuide.md` for the full German setup guide.

## Local development

Requirements on macOS:

- Xcode or Xcode Command Line Tools
- Swift 5.9+
- Python 3.9+
- BlackHole 2ch and BlackHole 16ch for real audio routing

Build unsigned app/pkg locally:

```bash
bash Scripts/build_release.sh
```

Artifacts are written to:

```text
dist/AudioDaBitch.app
dist/AudioDaBitch.pkg
dist/AudioDaBitch.zip
```

## GitHub release workflow

The workflow `.github/workflows/release.yml` builds the app on a macOS runner and attaches:

```text
AudioDaBitch.pkg
AudioDaBitch.zip
AudioDaBitch.streamDeckPlugin.zip
SHA256SUMS.txt
```

to a GitHub Release when a tag like `v0.4.2` is pushed.

## First push from Michel's Mac

Install GitHub CLI if needed:

```bash
brew install gh
```

Login:

```bash
gh auth login
```

Then run:

```bash
./push_to_github.command
```

The script creates or updates `Monoid12/AudioDaBitch`, commits the repository, pushes `main`, tags `v0.4.2`, and triggers GitHub Actions.

## GitHub settings

For a public repo with anonymous app update checks:

```text
Settings -> General -> Danger Zone -> Change repository visibility -> Public
Settings -> Actions -> General -> Actions permissions -> Allow all actions and reusable workflows
Settings -> Actions -> General -> Workflow permissions -> Read and write permissions
```

## Unsigned first release

This project currently builds an unsigned `.pkg`, because no Apple Developer ID certificate is available yet. macOS Gatekeeper may show a warning on first open.

## Stream Deck

The Stream Deck plugin scaffold is in:

```text
StreamDeckPlugin/com.micheldamhorst.audiodabitch.sdPlugin
```

It talks to AudioDaBitch via:

```text
http://127.0.0.1:49372/command
```

Supported examples:

```json
{"action":"adjust","path":"xpilot.gainDb","delta":1}
{"action":"adjust","path":"ducking.depthDb","delta":-1}
{"action":"toggle","path":"limiter.enabled"}
```

This covers Stream Deck XL key actions and Stream Deck + dial/encoder actions at the API level. The GitHub workflow attaches `AudioDaBitch.streamDeckPlugin.zip` as a release asset. The plugin should be tested on real Stream Deck XL and Stream Deck + hardware before broad distribution.
