# Hilfe / BlackHole Routing

## Merksatz

Alles geht zuerst in BlackHole, dann in AudioDaBitch, dann erst auf deinen Kopfhörer.

Richtig:

Discord -> BlackHole 2ch -> AudioDaBitch -> Kopfhörer
xPilot  -> BlackHole 16ch -> AudioDaBitch -> Kopfhörer

Falsch:

Discord/xPilot -> BlackHole + Kopfhörer

Ein Multi-Output-Gerät mit Kopfhörer erzeugt einen Direktweg. Dann hörst du Discord oder xPilot am Limiter vorbei.

## BlackHole installieren

Empfohlen sind zwei getrennte virtuelle Geräte:

- BlackHole 2ch für Discord
- BlackHole 16ch für xPilot

Mit Homebrew:

brew install --cask blackhole-2ch
brew install --cask blackhole-16ch

Danach bei Bedarf den Mac neu starten.

## Audio-MIDI-Setup

Öffne:

Programme -> Dienstprogramme -> Audio-MIDI-Setup

Setze nach Möglichkeit überall 48.000 Hz:

- BlackHole 2ch: 48.000 Hz
- BlackHole 16ch: 48.000 Hz
- Kopfhörer oder Audiointerface: 48.000 Hz

## Discord

Discord -> User Settings -> Voice & Video

- Input Device: normales Mikrofon
- Output Device: BlackHole 2ch

Nicht den Kopfhörer auswählen. Discord soll erst in AudioDaBitch ankommen.

## xPilot

xPilot -> Settings -> Audio

- Microphone/Input Device: normales Mikrofon
- Headset Device: BlackHole 16ch
- Speaker Device: BlackHole 16ch

Wenn COM1/COM2 getrennt verteilt werden, zunächst beide auf BlackHole 16ch setzen.

## AudioDaBitch

In AudioDaBitch:

- Discord Input: BlackHole 2ch
- xPilot Input: BlackHole 16ch
- Output: Kopfhörer, Audiointerface, MacBook Speaker oder AirPods

Nicht als AudioDaBitch Output verwenden:

- BlackHole 2ch
- BlackHole 16ch
- Multi-Output Device

## Test-Reihenfolge

1. AudioDaBitch öffnen.
2. Geräte aktualisieren.
3. Discord Input auf BlackHole 2ch stellen.
4. xPilot Input auf BlackHole 16ch stellen.
5. Output auf Kopfhörer oder Audiointerface stellen.
6. Audio starten.
7. Discord-Testton starten und Discord-Pegel prüfen.
8. xPilot-Funk testen und xPilot-Pegel prüfen.
9. Output-Pegel prüfen.
10. Panning testen.

## Fehlerdiagnose

Kein Ton:

- AudioDaBitch Output steht wirklich auf Kopfhörer/Audiointerface?
- Discord Output steht auf BlackHole 2ch?
- xPilot Output steht auf BlackHole 16ch?
- macOS Mikrofonberechtigung für AudioDaBitch erlaubt?
- Kein Multi-Output-Direktweg aktiv?

Inputs/Outputs leer:

- Engine neu starten klicken.
- Geräte aktualisieren klicken.
- Logs -> Log-ZIP erstellen und zur Diagnose senden.

Limiter wirkt nicht vollständig:

Wahrscheinlich läuft noch ein Direktweg am Limiter vorbei. Prüfe, dass Discord und xPilot nicht parallel direkt auf den Kopfhörer gehen.
