# AudioDaBitch 0.5.9

Installer-Fix für macOS PackageKit.

- Repariert die PKG-Installation nach `/Applications/AudioDaBitch.app`.
- Verhindert, dass macOS PackageKit `AudioDaBitch.app` an alte lokale Build-Pfade relocated.
- PKG-Build setzt das App-Bundle explizit auf nicht relocatable.
- Audio-Engine bleibt auf der stabilen 0.5.8/0.5.6-Basis mit funktionierendem `sounddevice==0.5.5`-Bootstrap.
- In-App-Update, Changelog und Hilfe bleiben aus 0.5.8 erhalten.
