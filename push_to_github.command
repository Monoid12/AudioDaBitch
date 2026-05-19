#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
OWNER="Monoid12"
REPO="AudioDaBitch"
VERSION="$(tr -d '\n' < VERSION)"
TAG="v$VERSION"
if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI fehlt. Installiere sie mit: brew install gh"
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI ist noch nicht angemeldet. Starte gh auth login ..."
  gh auth login
fi
if ! command -v git >/dev/null 2>&1; then
  echo "git fehlt. Installiere Xcode Command Line Tools."
  exit 1
fi
if [[ ! -d .git ]]; then
  git init
  git branch -M main
fi
if gh repo view "$OWNER/$REPO" >/dev/null 2>&1; then
  git remote remove origin >/dev/null 2>&1 || true
  git remote add origin "https://github.com/$OWNER/$REPO.git"
else
  gh repo create "$OWNER/$REPO" --public --source . --remote origin --push
fi
git add .
if ! git diff --cached --quiet; then
  git commit -m "Release $TAG"
else
  echo "Keine Dateiänderungen zu committen."
fi
git push -u origin main
if git rev-parse "$TAG" >/dev/null 2>&1; then
  git tag -f "$TAG"
else
  git tag "$TAG"
fi
git push origin "$TAG" --force
echo "Fertig. GitHub Actions baut jetzt das Release für $TAG."
echo "Prüfe: https://github.com/$OWNER/$REPO/actions"
