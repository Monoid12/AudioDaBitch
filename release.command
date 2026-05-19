#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
OWNER="Monoid12"
REPO="AudioDaBitch"
REMOTE="https://github.com/$OWNER/$REPO.git"
DEFAULT_VERSION="$(cat VERSION 2>/dev/null || echo 0.5.0)"

echo "AudioDaBitch Release Assistent"
echo "=============================="
echo "Repo: $OWNER/$REPO"
echo
read -r -p "Neue Version [$DEFAULT_VERSION]: " VERSION
VERSION="${VERSION:-$DEFAULT_VERSION}"
TAG="v$VERSION"
echo "$VERSION" > VERSION
perl -pi -e "s/let appVersion = \"[0-9]+\.[0-9]+\.[0-9]+\"/let appVersion = \"$VERSION\"/" Sources/AudioDaBitch/main.swift

echo
if [ -f CHANGELOG.md ]; then
  if ! grep -q "## $VERSION" CHANGELOG.md; then
    TMP="$(mktemp)"
    {
      echo "# Changelog"
      echo
      echo "## $VERSION - $(date +%Y-%m-%d)"
      echo "- Stabilitaets- und Bedienbarkeits-Release."
      echo "- Engine-Lifecycle verbessert."
      echo "- Kompaktere GUI fuer MacBook Pro 14 Zoll."
      echo "- Fenster-X fragt nach Beenden oder Minimieren."
      echo "- Einfacherer Release-Assistent."
      echo
      sed '1{/^# Changelog$/d;}' CHANGELOG.md
    } > "$TMP"
    mv "$TMP" CHANGELOG.md
  fi
fi
mkdir -p Resources
cp CHANGELOG.md Resources/CHANGELOG.md 2>/dev/null || true
rm -rf build dist __pycache__ Resources/__pycache__ Sources/**/__pycache__ 2>/dev/null || true

echo
./dev_check.command || true

echo
if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI fehlt. Installation: brew install gh"
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub Login wird gestartet..."
  gh auth login
fi
if [ ! -d .git ]; then git init; fi
if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "$REMOTE"
else
  git remote set-url origin "$REMOTE"
fi

echo
read -r -p "Release $TAG jetzt committen, pushen und bauen? [j/N]: " OK
case "$OK" in
  j|J|ja|JA|y|Y|yes|YES) ;;
  *) echo "Abgebrochen. Keine Aenderungen gepusht."; exit 0 ;;
esac

git add .
if git diff --cached --quiet; then
  echo "Keine Datei-Aenderungen zum Committen."
else
  git commit -m "AudioDaBitch $VERSION"
fi
git branch -M main
git push -u origin main
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG existiert lokal bereits."
else
  git tag -a "$TAG" -m "AudioDaBitch $VERSION"
fi
git push origin "$TAG"
echo
echo "GitHub Actions wurde gestartet. Beobachten mit:"
echo "  gh run watch"
echo
echo "Release-Seite: https://github.com/$OWNER/$REPO/releases"
