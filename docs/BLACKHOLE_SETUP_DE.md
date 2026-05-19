# AudioDaBitch: Detaillierte Einrichtung fuer Discord, xPilot und BlackHole

## 1. BlackHole-Geraete installieren

Benötigt werden zwei getrennte virtuelle Audiogeräte:

- BlackHole 2ch
- BlackHole 16ch

Beispiel mit Homebrew:

```bash
brew install --cask blackhole-2ch
brew install --cask blackhole-16ch
```

Danach Mac neu starten, falls die Geräte nicht sofort erscheinen.

Prüfen unter:

```text
Programme → Dienstprogramme → Audio-MIDI-Setup
```

Dort sollten erscheinen:

```text
BlackHole 2ch
BlackHole 16ch
Dein Kopfhörer / Audiointerface
```

## 2. Kein Multi-Output-Gerät mit Kopfhörer verwenden

Falls bereits Geräte wie diese erstellt wurden:

```text
Discord → BH2 + Kopfhörer
xPilot → BH16 + Kopfhörer
```

diese nicht verwenden. Sie können gelöscht oder umbenannt werden, damit sie nicht versehentlich ausgewählt werden.

Warum?

Ein Multi-Output-Gerät schickt Audio gleichzeitig an mehrere Ausgänge. Dadurch würdest du Discord oder xPilot einmal unbearbeitet direkt hören und zusätzlich noch einmal über AudioDaBitch. Der Limiter in AudioDaBitch würde dann nur auf den AudioDaBitch-Weg wirken, nicht auf den Direktweg.

Für dieses Projekt gilt daher:

```text
Apps gehen nur nach BlackHole.
Kopfhörer kommt erst nach AudioDaBitch.
```

## 3. Sample Rate angleichen

In Audio-MIDI-Setup:

```text
BlackHole 2ch       → 48.000 Hz
BlackHole 16ch      → 48.000 Hz
Kopfhörer/Interface → 48.000 Hz, falls möglich
```

48 kHz ist für Discord, xPilot und Gaming-/Simulator-Audio meist die sinnvollste Einstellung.

## 4. Discord konfigurieren

In Discord:

```text
User Settings → Voice & Video
```

Einstellungen:

```text
Input Device:  normales Mikrofon
Output Device: BlackHole 2ch
```

Wichtig:

```text
Nicht Kopfhörer auswählen.
Nicht Multi-Output-Gerät auswählen.
Nur BlackHole 2ch auswählen.
```

Ab diesem Moment hört man Discord nicht mehr direkt. Das ist korrekt, weil Discord nun erst in AudioDaBitch ankommen soll.

## 5. xPilot konfigurieren

In xPilot:

```text
Settings → Audio
```

Einstellungen:

```text
Microphone/Input Device: normales Mikrofon
Headset Device:          BlackHole 16ch
Speaker Device:          BlackHole 16ch
```

Damit gehen alle xPilot-Ausgaben in AudioDaBitch.

Wichtig:

```text
Nicht Kopfhörer auswählen.
Nicht Multi-Output-Gerät auswählen.
Nur BlackHole 16ch auswählen.
```

Falls COM1/COM2 in xPilot getrennt auf Headset/Speaker verteilt werden, beide Geräte zunächst auf BlackHole 16ch setzen, damit kein Funkverkehr an AudioDaBitch vorbeiläuft.

## 6. AudioDaBitch konfigurieren

In AudioDaBitch:

```text
Discord Input: BlackHole 2ch
xPilot Input:  BlackHole 16ch
Output:        Kopfhörer / Audiointerface
Limiter:       aktiv auf Master/Output
```

Der AudioDaBitch-Output muss das echte Abhörgerät sein, zum Beispiel:

```text
USB-Audiointerface
Kopfhörer
MacBook Speakers
AirPods
```

Nicht verwenden als AudioDaBitch-Output:

```text
BlackHole 2ch
BlackHole 16ch
Aggregate Device
Multi-Output Device
```

Sonst kann es zu Stille, Routing-Schleifen oder Rückkopplungen kommen.

## Variante mit getrennten Inputs

Dies ist die beste Variante:

```text
Source 1 / Discord:
Device: BlackHole 2ch
Channels: 1/2

Source 2 / xPilot:
Device: BlackHole 16ch
Channels: 1/2

Master Output:
Device: Kopfhörer / Audiointerface
Limiter: aktiv
```

Signalfluss:

```text
Discord → BlackHole 2ch → AudioDaBitch Discord-Kanal ┐
                                                       ├→ Master-Limiter → Kopfhörer
xPilot  → BlackHole 16ch → AudioDaBitch xPilot-Kanal  ┘
```

## Falls nur ein einziges Input-Gerät unterstützt wird

Dann ein Aggregate Device erstellen.

Wichtig:

```text
Aggregate Device = mehrere Inputs werden zu einem Gerät zusammengefasst
Multi-Output Device = ein Output wird an mehrere Geräte gleichzeitig geschickt
```

Für dieses Projekt ist nur ein Aggregate Device sinnvoll, kein Multi-Output Device.

### Aggregate Device erstellen

Öffnen:

```text
Programme → Dienstprogramme → Audio-MIDI-Setup
```

Dann:

```text
+ → Hauptgerät erstellen / Create Aggregate Device
```

Name:

```text
ADB Inputs
```

Aktivieren:

```text
BlackHole 2ch
BlackHole 16ch
```

Optional zusätzlich, falls AudioDaBitch auch das Mikrofon verarbeiten soll:

```text
Mikrofon / Audiointerface Input
```

Beispielhafte Kanalbelegung:

```text
Kanäle 1/2:  Discord von BlackHole 2ch
Kanäle 3/4:  xPilot von BlackHole 16ch
```

Dann in AudioDaBitch:

```text
Input Device: ADB Inputs
Discord:      Kanäle 1/2
xPilot:       Kanäle 3/4
Output:       Kopfhörer / Audiointerface
```

Discord und xPilot selbst bleiben trotzdem auf den einzelnen BlackHole-Geräten:

```text
Discord Output: BlackHole 2ch
xPilot Output:  BlackHole 16ch
```

Nicht auf `ADB Inputs`.

## Korrektes finales Routing

Discord:

```text
Input Device:  Mikrofon
Output Device: BlackHole 2ch
```

xPilot:

```text
Microphone/Input: Mikrofon
Headset Device:   BlackHole 16ch
Speaker Device:   BlackHole 16ch
```

AudioDaBitch, Variante mit getrennten Inputs:

```text
Discord Input: BlackHole 2ch, Kanäle 1/2
xPilot Input:  BlackHole 16ch, Kanäle 1/2
Output:        Kopfhörer / Audiointerface
Limiter:       aktiv
```

AudioDaBitch, Variante mit Aggregate Device:

```text
Input Device: ADB Inputs
Discord:      Kanäle 1/2
xPilot:       Kanäle 3/4
Output:       Kopfhörer / Audiointerface
Limiter:      aktiv
```

## Test-Reihenfolge

1. AudioDaBitch öffnen.
2. AudioDaBitch-Output auf Kopfhörer oder Audiointerface stellen.
3. Discord-Output auf BlackHole 2ch stellen.
4. Discord-Testton oder Voice-Call starten.
5. In AudioDaBitch prüfen, ob Signal auf dem Discord-Kanal ankommt.
6. Prüfen, ob Discord über AudioDaBitch auf dem Kopfhörer hörbar ist.
7. xPilot-Output auf BlackHole 16ch stellen.
8. xPilot-Funk testen.
9. In AudioDaBitch prüfen, ob Signal auf dem xPilot-Kanal ankommt.
10. Limiter aktivieren und prüfen, ob laute Pegel abgefangen werden.

## Fehlerdiagnose

### Kein Ton hörbar

Prüfen:

```text
AudioDaBitch Output steht auf Kopfhörer / Audiointerface
Discord Output steht auf BlackHole 2ch
xPilot Output steht auf BlackHole 16ch
AudioDaBitch hat macOS-Mikrofonberechtigung
richtige Kanäle im Aggregate Device gewählt
```

### Kein Signal in AudioDaBitch

Prüfen:

```text
macOS Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon
AudioDaBitch muss dort erlaubt sein, weil virtuelle Audio-Inputs unter macOS oft wie Mikrofone behandelt werden.
```

### Discord und xPilot sind vermischt

Dann zeigen beide Apps wahrscheinlich auf dasselbe BlackHole-Gerät.

Richtig:

```text
Discord → BlackHole 2ch
xPilot  → BlackHole 16ch
```

Falsch:

```text
Discord → BlackHole 2ch
xPilot  → BlackHole 2ch
```

### Limiter wirkt nicht vollständig

Dann läuft wahrscheinlich ein Direktweg am AudioDaBitch-Limiter vorbei.

Prüfen, dass kein Multi-Output-Gerät mit Kopfhörer verwendet wird.

Richtig:

```text
Discord/xPilot → BlackHole → AudioDaBitch → Kopfhörer
```

Falsch:

```text
Discord/xPilot → BlackHole + Kopfhörer
```

## Merksatz

```text
Alles erst in BlackHole,
dann in AudioDaBitch,
dann erst auf den Kopfhörer.
```

Kein paralleles Direkt-Monitoring über Multi-Output, wenn der Limiter wirklich auf Discord und xPilot wirken soll.
