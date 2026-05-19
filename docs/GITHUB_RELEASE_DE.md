# GitHub Release Workflow

Ab 0.5.0 soll der normale Ablauf nur noch ein Befehl sein:

```bash
./release.command
```

Der Assistent erledigt:

1. Version setzen.
2. App-Version in Swift aktualisieren.
3. Changelog-Eintrag vorbereiten.
4. Dev-Check starten.
5. Commit erstellen.
6. Separat fragen, bevor `main` gepusht wird.
7. Separat fragen, bevor Tag `vX.Y.Z` erstellt und gepusht wird.
8. GitHub Actions Build starten.

Voraussetzungen:

```bash
brew install gh
gh auth login
```

GitHub Actions erstellt dann `AudioDaBitch.pkg`, `AudioDaBitch.app.zip` und `SHA256SUMS.txt`.
