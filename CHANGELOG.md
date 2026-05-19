# Changelog

## 0.5.9

- PKG-Installation repariert: `AudioDaBitch.app` wird im Installer nicht mehr an alte lokale Build-Pfade relocated.
- PKG-Build setzt `BundleIsRelocatable=false` und `BundleHasStrictIdentifier=true` für das App-Bundle.
- Audio-Basis aus 0.5.8 bleibt unverändert: stabiler 0.5.6-Mixer mit `sounddevice==0.5.5`.

## 0.5.8

- Stabile Audio-Basis aus 0.5.6 wiederhergestellt: gleicher Mixer, gleiches Panning, gleicher Safe-Mode, wieder `sounddevice==0.5.5`.
- Engine-Shutdown repariert, damit `/shutdown` sauber beendet und keine alten Engine-Prozesse liegen bleiben.
- In-App-Update ergänzt: GitHub-Release-Prüfung, sichtbarer blauer Update-Badge, Download von `AudioDaBitch.pkg`, Engine-Stopp, Installer-Start und Neustart der App nach dem Installer.
- PKG-Build gehärtet: der Build bricht ab, wenn das Paket keine `Applications/AudioDaBitch.app` mit `Resources/engine.py` enthält.
- `postinstall` prüft nach der Installation, ob `/Applications/AudioDaBitch.app` wirklich vorhanden und vollständig ist.
- Changelog- und Hilfe-Tabs bleiben sichtbar gefüllt; keine leeren schwarzen Textflächen.
- Developer Tool entfernt; `release.command` ist jetzt der robuste Release-Assistent mit eingebauten Checks und separaten Abfragen vor Push und Tag.
- `dev_check.command` prüft Engine-Version, Swift-Version, App-Bundle, Icon, PKG-Payload und Git-Artefakte.

## 0.5.7

- Installer-Cleanup und erste Update-Hinweise ergänzt.
- Developer Tool experimentell hinzugefügt.

## 0.5.6

- Audio-Seite stabilisiert: 48-kHz-Safe-Mode, größere Puffer und Ringbuffer gegen kurze Timing-Schwankungen.
- Geräteauswahl repariert: Inputs und Outputs werden aus der Engine-Geräteliste geladen und per Device-ID gespeichert.
- Discord-Panning, xPilot-Panning, Ducking, Limiting und xPilot Auto-Leveling sichtbar bedienbar.
- Changelog als eigener Tab und Hilfe/BlackHole-Routing sichtbar gefüllt.
- App-Icon und Log-ZIP wieder eingebunden.
