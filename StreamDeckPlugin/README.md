# AudioDaBitch Stream Deck Plugin Scaffold

This is a first plugin scaffold for Stream Deck XL and Stream Deck +.

It controls AudioDaBitch through the local API:

```text
http://127.0.0.1:49372/command
```

The manifest uses Stream Deck SDKVersion 2 and includes:

- Keypad actions for Stream Deck XL.
- Encoder actions for Stream Deck + dials.

Before publishing, bundle and test with Elgato's official tooling. The current SDK expects a recent Stream Deck app and Node.js runtime; the scaffold manifest is set to Node.js 24.

Typical setup:

```bash
npm install -g @elgato/cli@latest
streamdeck validate com.micheldamhorst.audiodabitch.sdPlugin
streamdeck pack com.micheldamhorst.audiodabitch.sdPlugin
```

The plugin contains no GitHub token and no secret.
