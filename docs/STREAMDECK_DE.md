# Stream Deck Support

AudioDaBitch stellt eine lokale HTTP-Schnittstelle bereit, sobald die Audio-Engine laeuft:

```text
http://127.0.0.1:49342/api/status
http://127.0.0.1:49342/api/config
http://127.0.0.1:49342/api/adjust
```

Das enthaltene Plugin-Geruest unter:

```text
streamdeck/com.micheldamhorst.audiodabitch.sdPlugin
```

ist fuer folgende Geraete vorgesehen:

- Stream Deck XL: Keypad-Actions
- Stream Deck +: Encoder/Dial-Actions

## Verfuegbare Aktionen

Keypad / Stream Deck XL:

- Ducking an/aus
- xPilot Auto-Leveler an/aus
- xPilot Gain +1 dB
- xPilot Gain -1 dB
- Ducking-Tiefe +1 dB
- Ducking-Tiefe -1 dB
- Master Gain +1 dB
- Master Gain -1 dB

Encoder / Stream Deck +:

- Dial dreht je nach Einstellung:
  - xPilot Gain
  - Ducking-Tiefe
  - Master Gain
  - xPilot Target Level
- Dial Push toggelt Ducking oder xPilot Auto-Leveler.

## Installation des Plugin-Assets

Nach einem GitHub Release entsteht:

```text
AudioDaBitch.streamDeckPlugin
```

Doppelklick installiert es in Stream Deck.

## Wichtig

Die Stream Deck Aktionen koennen nur arbeiten, wenn AudioDaBitch laeuft und die Audio-Engine gestartet wurde.
