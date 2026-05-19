# GitHub Einrichtung für AudioDaBitch

Empfohlene Konfiguration:

```text
Owner: Monoid12
Repository: AudioDaBitch
Visibility: Public
Release Asset: AudioDaBitch.pkg
Lizenz: keine Open-Source-Lizenz / All rights reserved
```

Warum Public?

Die App kann `https://api.github.com/repos/Monoid12/AudioDaBitch/releases/latest` ohne Token lesen. Dadurch erscheint der Update-Button automatisch, sobald ein Public Release mit `AudioDaBitch.pkg` vorhanden ist.

## Repo erstellen

```bash
gh auth login
gh repo create Monoid12/AudioDaBitch --public
```

Oder über GitHub Web:

```text
New repository -> Owner Monoid12 -> Name AudioDaBitch -> Public
```

## Actions Rechte

Im Repository:

```text
Settings -> Actions -> General
Actions permissions -> Allow all actions and reusable workflows
Workflow permissions -> Read and write permissions
```

## Push

Im entpackten Repository-Paket:

```bash
./push_to_github.command
```

Das Script pushed `main` und Tag `v0.4.3`. Danach baut GitHub Actions automatisch `AudioDaBitch.pkg` und erstellt/aktualisiert den Release.
