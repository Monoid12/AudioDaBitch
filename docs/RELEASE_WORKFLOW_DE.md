# Release-Workflow für GitHub

Empfohlenes Setup:

```text
Owner: Monoid12
Repo:  AudioDaBitch
Visibility: Public
Release Asset: AudioDaBitch.pkg
```

## Einmalige Vorbereitung

1. Repo auf GitHub erstellen oder sichtbar machen.
2. In GitHub Actions Schreibrechte erlauben:

```text
Settings -> Actions -> General
Actions permissions: Allow all actions and reusable workflows
Workflow permissions: Read and write permissions
```

3. GitHub CLI lokal anmelden:

```bash
gh auth login
```

## Push

Im Projektordner:

```bash
./push_to_github.command
```

Das Script committed den Stand, pusht `main` und setzt den Tag `v0.4.2`.

## Automatischer Release

Bei einem Tag `v*.*.*` startet GitHub Actions den Workflow:

```text
.github/workflows/release.yml
```

Erzeugte Assets:

```text
AudioDaBitch.pkg
AudioDaBitch.zip
AudioDaBitch.streamDeckPlugin.zip
SHA256SUMS.txt
```

## In-App Updates

Die App prüft:

```text
https://api.github.com/repos/Monoid12/AudioDaBitch/releases/latest
```

Wenn `tag_name` neuer ist als die installierte Version und ein `.pkg`-Asset vorhanden ist, erscheint in der App der Update-Button. Der Button lädt `AudioDaBitch.pkg` in den Downloads-Ordner und öffnet danach die macOS Installer-App.
