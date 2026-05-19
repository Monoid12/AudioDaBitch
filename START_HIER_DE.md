# AudioDaBitch 0.5.0 Beta - Start hier

Diese Version ist ein Stabilitaets- und Bedienbarkeits-Release.

## Was neu ist

- Kompaktere App-GUI fuer ein MacBook Pro 14 Zoll.
- Rotes Fenster-X fragt jetzt nach **Beenden**, **Minimieren** oder **Abbrechen**.
- Beim Beenden wird die Audio-Engine gestoppt.
- Engine-Start/Stop/Neustart sind klarer getrennt.
- Alte haengende Engine-Prozesse werden beim Start/Stop entfernt.
- Output- und Input-Geraete werden per stabiler Device-Index-Auswahl gespeichert.
- Panning bleibt links/rechts pro Quelle erhalten.
- GitHub-Release-Prozess wurde vereinfacht: `./release.command`.

## Empfohlene Arbeitsstruktur

```text
~/Documents/CODING/AudioDaBitch/
├── AudioDaBitch_repo/
└── Patches/
```

## Release starten

Im Repo-Ordner:

```bash
./release.command
```

Der Assistent fragt die Version ab, prueft die Dateien, erstellt Commit/Tag und startet GitHub Actions.

## Audio starten

1. Discord Input: BlackHole 2ch
2. xPilot Input: BlackHole 16ch
3. Output: echte Kopfhoerer / Audiointerface
4. Button: Audio starten

Keine Multi-Output-Geraete verwenden, sonst laeuft Audio am Limiter vorbei.
