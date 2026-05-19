# AudioDaBitch Changelog

## 0.5.9

Installer-Fix.

- Das PKG installiert `AudioDaBitch.app` zuverlässig nach `/Applications`.
- macOS PackageKit darf die App nicht mehr zu alten lokalen Build-Ordnern verschieben.
- Audio-Engine bleibt auf der stabilen 0.5.8/0.5.6-Basis.

## 0.5.8

Restore-/Update-/Release-Fix.

- Audio-Engine bleibt auf der stabilen 0.5.6-Basis.
- `sounddevice` wird wieder mit der funktionierenden Version 0.5.5 gebootstrapped.
- `/shutdown` beendet die Engine sauber und räumt die PID-Datei auf.
- Update-Tab prüft GitHub Releases von `Monoid12/AudioDaBitch`.
- Bei neuer Version erscheint ein blauer Update-Badge und der Button „Update installieren“.
- Das Update lädt `AudioDaBitch.pkg`, stoppt die Engine, startet den Installer und öffnet danach die neue App.
- PKG-Build und `postinstall` prüfen, ob `/Applications/AudioDaBitch.app` wirklich installiert wird.
- Hilfe und Changelog bleiben als eigene, helle Textbereiche sichtbar gefüllt.
- Das experimentelle Developer Tool wurde entfernt; Releases laufen über `release.command`.

## 0.5.6

Audioqualität / Stabilität / Changelog-Fix.

- Safe-Mode für stabilere Ausgabe: 48 kHz, größerer Audio-Puffer und hohe Latenz als Standard.
- Ringbuffer zwischen Input- und Output-Streams, damit kurze Timing-Schwankungen weniger stottern.
- Audio-Diagnose im Hauptfenster: Sample Rate, Blockgröße, Latenz und Callback-Fehler.
- Button „Audio stabilisieren“ setzt sichere Audio-Parameter und startet Audio neu.
- Changelog als eigener sichtbarer Tab.
- Hilfe/BlackHole-Routing sichtbar gefüllt.
- Log-ZIP im Logs-Tab.
