# Changelog

## 0.5.1 - 2026-05-19
- Stabilitaets- und Bedienbarkeits-Release.
- Engine-Lifecycle umgebaut: alte Engine-Prozesse werden vor Start/Stop entfernt.
- Keine GUI-Abhaengigkeit vom alten lokalen HTTP-State der 0.4.x-App.
- Kompaktere App-GUI fuer MacBook Pro 14 Zoll.
- Fenster-X fragt nach Beenden, Minimieren oder Abbrechen.
- Beenden stoppt die Audio-Engine.
- Minimize-/Fenster-anzeigen-Menue eingebaut.
- Output- und Input-Auswahl werden per stabiler Device-ID/Index gespeichert.
- xPilot Auto-Leveler bleibt als eigene Einstellseite erhalten.
- GitHub-Update-Tab laedt das Release-PKG und oeffnet den macOS Installer.
- Vereinfachter Release-Prozess ueber `./release.command`.
- `./dev_check.command` fuer Vorabpruefung eingebaut.

## 0.4.5
- Kombiniert Swift-Concurrency-Buildfix und Apple-Silicon-Enginefix.

## 0.4.4
- Engine-Fix vorbereitet, Build nicht als finales Release verwenden.

## 0.4.3
- Swift-Concurrency-Buildfix fuer GitHub Actions.
