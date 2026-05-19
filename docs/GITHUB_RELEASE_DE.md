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
6. Main pushen.
7. Tag `vX.Y.Z` erstellen.
8. GitHub Actions Build starten.

Voraussetzungen:

```bash
brew install gh
gh auth login
```

GitHub Actions erstellt dann `AudioDaBitch.pkg`, `AudioDaBitch.zip`, Stream-Deck-Plugin und `SHA256SUMS.txt`.
