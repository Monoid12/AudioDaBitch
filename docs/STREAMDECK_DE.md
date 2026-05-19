# Stream Deck Support

AudioDaBitch stellt eine lokale Control-API bereit:

```text
http://127.0.0.1:49372
```

Diese API ist absichtlich nur lokal auf `127.0.0.1` erreichbar und dient der Steuerung über Stream Deck XL und Stream Deck +.

## Unterstützte Aktionen

Für Stream Deck XL, also normale Tasten:

```text
xPilot Gain +1 dB
xPilot Gain -1 dB
Discord Gain +1 dB
Discord Gain -1 dB
Ducking stärker
Ducking schwächer
Limiter an/aus
```

Für Stream Deck +, also Drehregler:

```text
Dial: xPilot Gain
Dial: Ducking-Tiefe
Dial Press: Reset auf Standardwert
```

Der Code ist bewusst als erster Plugin-Scaffold angelegt. Weitere Aktionen wie Master-Gain, Auto-Level Toggle oder Limiter Ceiling können direkt über denselben `/command`-Endpoint ergänzt werden.

## Plugin-Ordner

Die vorbereitete Plugin-Struktur liegt hier:

```text
StreamDeckPlugin/com.micheldamhorst.audiodabitch.sdPlugin
```

Im GitHub Release wird zusätzlich ein ZIP mit dem Plugin-Ordner erstellt:

```text
AudioDaBitch.streamDeckPlugin.zip
```

## API-Beispiele

Status abrufen:

```bash
curl http://127.0.0.1:49372/state
```

Geräte abrufen:

```bash
curl http://127.0.0.1:49372/devices
```

xPilot Gain um 1 dB erhöhen:

```bash
curl -X POST http://127.0.0.1:49372/command \
  -H 'Content-Type: application/json' \
  -d '{"action":"adjust","path":"xpilot.gainDb","delta":1}'
```

Ducking-Tiefe stärker machen:

```bash
curl -X POST http://127.0.0.1:49372/command \
  -H 'Content-Type: application/json' \
  -d '{"action":"adjust","path":"ducking.depthDb","delta":-1}'
```

Limiter toggeln:

```bash
curl -X POST http://127.0.0.1:49372/command \
  -H 'Content-Type: application/json' \
  -d '{"action":"toggle","path":"limiter.enabled"}'
```

xPilot Auto-Level an/aus toggeln:

```bash
curl -X POST http://127.0.0.1:49372/command \
  -H 'Content-Type: application/json' \
  -d '{"action":"toggle","path":"xpilotAutoLevel.enabled"}'
```

## Hinweis

Der Stream Deck Support ist in 0.4.3 als erster Plugin-Entwurf enthalten. Er sollte auf echter Stream Deck XL und Stream Deck + Hardware getestet und danach verfeinert werden. Die Manifest-Struktur verwendet Keypad-Aktionen für normale Stream-Deck-Tasten und Encoder-Aktionen für Stream Deck + Drehregler.
