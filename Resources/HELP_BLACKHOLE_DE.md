# Hilfe / BlackHole Routing

## Ziel

Discord und xPilot sollen zuerst in virtuelle BlackHole-Geräte laufen. AudioDaBitch verarbeitet beide Quellen, macht Ducking, Panning, Leveling und Limiting und gibt erst danach auf den Kopfhörer aus.

## Richtiger Signalfluss

Discord -> BlackHole 2ch -> AudioDaBitch Discord -> Output

xPilot -> BlackHole 16ch -> AudioDaBitch xPilot -> Output

AudioDaBitch Output -> Kopfhörer / Headset / Audiointerface

## Wichtig

Kein Multi-Output-Gerät mit Kopfhörer verwenden. Sonst hörst du Discord oder xPilot zusätzlich direkt und der Limiter wirkt nicht vollständig.

## Empfohlene macOS Audio-MIDI-Einstellung

- BlackHole 2ch: 48.000 Hz
- BlackHole 16ch: 48.000 Hz
- Kopfhörer / Headset / Audiointerface: 48.000 Hz, falls verfügbar

## Discord

- Input Device: normales Mikrofon
- Output Device: BlackHole 2ch

## xPilot

- Microphone/Input: normales Mikrofon
- Headset Device: BlackHole 16ch
- Speaker Device: BlackHole 16ch

## AudioDaBitch

- Discord Input: BlackHole 2ch
- xPilot Input: BlackHole 16ch
- Output: echter Kopfhörer / Headset / Audiointerface

## Wenn Audio stottert

1. In AudioDaBitch auf „Audio stabilisieren“ klicken.
2. In Audio-MIDI-Setup alle beteiligten Geräte auf 48.000 Hz stellen.
3. Bluetooth/AirPods testweise vermeiden, wenn besonders niedrige Latenz gebraucht wird.
4. Logs -> Log-ZIP erstellen und schicken.
