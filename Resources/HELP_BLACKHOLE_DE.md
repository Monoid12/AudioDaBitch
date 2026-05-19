# AudioDaBitch Hilfe: BlackHole Routing

## Ziel
Discord und xPilot sollen nicht direkt auf den Kopfhörer gehen. Sie gehen zuerst in BlackHole, dann durch AudioDaBitch, und erst danach auf deinen Kopfhörer oder dein Audiointerface.

## Korrektes Routing

Discord:
- Input Device: dein normales Mikrofon
- Output Device: BlackHole 2ch

xPilot:
- Microphone/Input: dein normales Mikrofon
- Headset Device: BlackHole 16ch
- Speaker Device: BlackHole 16ch

AudioDaBitch:
- Discord Input: BlackHole 2ch
- xPilot Input: BlackHole 16ch
- Output: dein Kopfhörer oder Audiointerface

## Wichtig
Kein Multi-Output-Gerät mit Kopfhörer verwenden. Sonst hörst du Discord oder xPilot einmal direkt und einmal über AudioDaBitch. Dann wirken Ducking und Limiter nicht vollständig.

## Merksatz
Alles erst in BlackHole, dann in AudioDaBitch, dann erst auf den Kopfhörer.

## Fehlerdiagnose
Wenn keine Geräte auswählbar sind, klicke zuerst auf „Engine reparieren“ und danach auf „Geräte aktualisieren“. Wenn weiterhin keine Geräte erscheinen, öffne Logs und erstelle eine Log-ZIP.
