# AudioDaBitch Hilfe / BlackHole Routing

## Ziel
Discord und xPilot sollen nicht direkt auf den Kopfhörer gehen. Beide Apps müssen zuerst in BlackHole gehen, dann verarbeitet AudioDaBitch Pegel, Ducking, Panning und Limiter, und erst danach geht das Signal auf deinen Kopfhörer.

## Richtige Geräte
- Discord Output: BlackHole 2ch
- xPilot Headset/Speaker: BlackHole 16ch
- AudioDaBitch Output: echter Kopfhörer, Audiointerface, MacBook Speakers oder AirPods

## Nicht verwenden
Kein Multi-Output-Gerät mit Kopfhörer verwenden. Sonst hörst du Discord oder xPilot direkt und zusätzlich über AudioDaBitch. Dann wirken Limiter, Ducking und Leveler nicht vollständig.

## Sample Rate
In Audio-MIDI-Setup möglichst alles auf 48.000 Hz stellen:
- BlackHole 2ch
- BlackHole 16ch
- Kopfhörer / Audiointerface

## Test
1. AudioDaBitch öffnen.
2. Discord Input auf BlackHole 2ch setzen.
3. xPilot Input auf BlackHole 16ch setzen.
4. Output auf Kopfhörer oder Audiointerface setzen.
5. Audio starten.
6. Discord-Testton abspielen und Pegelanzeige prüfen.
7. xPilot-Funk testen und Pegelanzeige prüfen.

## Merksatz
Alles erst in BlackHole, dann in AudioDaBitch, dann erst auf den Kopfhörer.
