# Changelog

Alle relevanten Aenderungen an AudioDaBitch werden in dieser Datei dokumentiert. Die App zeigt diese Datei lokal an und ergaenzt sie um die Release Notes des neuesten GitHub Releases.

## [0.5.0] - 2026-05-19

### Added

- Native macOS AppKit GUI statt Browser/Tkinter/JXA.
- GitHub Update-Check fuer `Monoid12/AudioDaBitch`.
- Update-Button erscheint nur, wenn das neueste GitHub Release neuer ist als die installierte Version.
- Changelog-Tab in der App.
- Detaillierte BlackHole/Discord/xPilot-Einrichtungsanleitung in der App und unter `docs/BLACKHOLE_SETUP_DE.md`.
- Log-Verzeichnis `~/Library/Logs/AudioDaBitch/`.
- Buttons: Logs oeffnen, Diagnose exportieren, Log-ZIP erstellen.
- xPilot Auto-Leveler/AGC:
  - Zielpegel einstellbar.
  - schneller Abwaerts-Regelweg fuer zu laute VATSIM-Stationen.
  - kontrollierter Aufwaerts-Regelweg fuer zu leise Stationen.
  - Gate gegen Noise-Boosting bei Stille.
  - Peak-Guard gegen harte Uebersteuerung.
- Lokale HTTP-Control-API fuer externe Controller und Stream Deck.
- Stream Deck Plugin-Geruest fuer Stream Deck XL und Stream Deck +.
- GitHub Actions Workflow fuer unsigned `.pkg` Release mit macOS Installer-Fortschrittsanzeige.

### Changed

- Python-Audio-Backend bleibt unsichtbar im Hintergrund und wird durch die native App gestartet. Es oeffnet beim normalen App-Start kein Terminal.
- Python-Abhaengigkeiten wurden auf `numpy` und `sounddevice` reduziert; PyObjC wird nicht mehr benoetigt.
- Logging wurde von einer einzelnen Logdatei auf ein eigenes Verzeichnis umgestellt.

### Fixed

- Entfernt den bisherigen JXA/AppleScript-Startpfad, der in deiner Diagnose mit Syntaxfehler `334:335` abgebrochen ist.
- Vermeidet den frueheren Tkinter/Tcl-Pfad der alten GamingAudioLimiter-Version.

## [0.4.1] - 2026-05-19

### Known issue

- Die Diagnose zeigte, dass die Pakete installiert wurden, der App-Start aber an einem JXA/AppleScript-Syntaxfehler `334:335` scheiterte.

## [0.4.0] - 2026-05-19

### Added

- Umbenennung zu AudioDaBitch.
- Erstes App-Icon.
- Erste native GUI-Idee.
