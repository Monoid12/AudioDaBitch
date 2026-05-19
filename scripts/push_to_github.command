#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OWNER="Monoid12"
REPO="AudioDaBitch"
TAG="v0.5.0"
REMOTE="https://github.com/$OWNER/$REPO.git"

echo "AudioDaBitch GitHub Push"
echo "=========================="
echo "Ziel: $REMOTE"
echo "Tag:  $TAG"
echo

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI fehlt. Bitte installieren: brew install gh"
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub Login wird gestartet..."
  gh auth login
fi
if [ ! -d .git ]; then
  git init
fi
if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "$REMOTE"
else
  git remote set-url origin "$REMOTE"
fi
git add .
if git diff --cached --quiet; then
  echo "Keine neuen Aenderungen zum Committen."
else
  git commit -m "AudioDaBitch 0.5.0 release structure"
fi
git branch -M main
git push -u origin main
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG existiert lokal bereits."
else
  git tag -a "$TAG" -m "AudioDaBitch 0.5.0"
fi
git push origin "$TAG"
echo
echo "Fertig. GitHub Actions sollte jetzt den Release bauen."
echo "Repo: https://github.com/$OWNER/$REPO/actions"
