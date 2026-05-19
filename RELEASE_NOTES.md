# AudioDaBitch 0.5.8

Restore-/Update-/Release-Fix.

- Audio-Engine auf die stabile 0.5.6-Basis zurückgesetzt, inklusive funktionierendem `sounddevice==0.5.5`-Bootstrap.
- Sauberer Engine-Shutdown, damit keine mehrfachen Engine-Prozesse hängen bleiben.
- In-App-Update: neuer Release-Check für `Monoid12/AudioDaBitch`, sichtbarer blauer Badge, Download von `AudioDaBitch.pkg`, Engine-Stopp, Installer-Start und App-Neustart.
- PKG-Build und `postinstall` prüfen zuverlässig, ob `/Applications/AudioDaBitch.app` enthalten und installiert ist.
- Changelog und Hilfe/BlackHole-Routing sind eigene, gefüllte Tabs.
- Developer Tool entfernt; `release.command` und `dev_check.command` übernehmen Release- und Prüfaufgaben robuster.
