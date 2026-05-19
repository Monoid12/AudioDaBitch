# Fehlerdiagnose

## Kein Ton hörbar

Prüfen:

```text
AudioDaBitch Output steht auf Kopfhörer / Audiointerface
Discord Output steht auf BlackHole 2ch
xPilot Output steht auf BlackHole 16ch
AudioDaBitch hat macOS-Mikrofonberechtigung
richtige Kanäle im Aggregate Device gewählt
```

## Kein Signal in AudioDaBitch

Prüfen:

```text
macOS Systemeinstellungen -> Datenschutz & Sicherheit -> Mikrofon
```

AudioDaBitch muss dort erlaubt sein, weil virtuelle Audio-Inputs unter macOS oft wie Mikrofone behandelt werden.

## Discord und xPilot sind vermischt

Dann zeigen beide Apps wahrscheinlich auf dasselbe BlackHole-Gerät.

Richtig:

```text
Discord -> BlackHole 2ch
xPilot  -> BlackHole 16ch
```

Falsch:

```text
Discord -> BlackHole 2ch
xPilot  -> BlackHole 2ch
```

## Limiter wirkt nicht vollständig

Dann läuft wahrscheinlich ein Direktweg am AudioDaBitch-Limiter vorbei.

Prüfen, dass kein Multi-Output-Gerät mit Kopfhörer verwendet wird.

Richtig:

```text
Discord/xPilot -> BlackHole -> AudioDaBitch -> Kopfhörer
```

Falsch:

```text
Discord/xPilot -> BlackHole + Kopfhörer
```

## Log-Dateien

AudioDaBitch schreibt Logs hierhin:

```text
~/Library/Logs/AudioDaBitch/
```

Wichtige Dateien:

```text
app.log
engine.log
setup.log
diagnostics_YYYYMMDD_HHMMSS.zip
```

In der App gibt es Buttons für:

```text
Logs öffnen
Diagnose exportieren
```

## Bisherige bekannte Fehlerursachen

Frühere Builds hatten zwei relevante Probleme:

1. Tkinter/Tk konnte auf macOS unter Rosetta abstürzen.
2. Der JXA/AppleScript-Launcher konnte mit einem Syntaxfehler abbrechen.

Version 0.4.3 entfernt beide Startpfade. Die App nutzt keine Tkinter-GUI und keine JXA/AppleScript-GUI.
