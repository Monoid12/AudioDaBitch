#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/common.sh"
REPO="$(repo_path)"
echo "Repo: $REPO"
cd "$REPO"
clean_caches
mkdir -p Resources
printf '%s\n' "$VERSION_TARGET" > VERSION
# Update known version strings only, keep audio logic untouched.
python3 - <<'PY'
from pathlib import Path
import re
v = Path('VERSION').read_text().strip()
for fn in ['Sources/AudioDaBitch/main.swift','Resources/engine.py','RELEASE_NOTES.md','Resources/CHANGELOG.md','CHANGELOG.md']:
    p=Path(fn)
    if not p.exists(): continue
    s=p.read_text()
    s=re.sub(r'0\.5\.[0-9]+', v, s)
    p.write_text(s)
# Ensure Changelog content exists
for fn in ['Resources/CHANGELOG.md','CHANGELOG.md']:
    p=Path(fn)
    old=p.read_text() if p.exists() else ''
    entry=f"""# AudioDaBitch Changelog\n\n## 0.5.7\n- Update-Tab zeigt sichtbaren Hinweis/Badge fuer neue Releases.\n- Developer Tool: eingebettete Skripte, eigenes Icon, Ausgabefenster.\n- Release-Workflow nutzt lokale GitHub-CLI-Anmeldung.\n- Audio-Engine aus 0.5.6 bleibt unveraendert, um funktionierenden Sound nicht anzufassen.\n\n"""
    if '## 0.5.7' not in old:
        if old.startswith('# AudioDaBitch Changelog'):
            old = old.replace('# AudioDaBitch Changelog\n', entry, 1)
        else:
            old = entry + old
    p.write_text(old)
# Help text must not be empty
p=Path('Resources/HELP_BLACKHOLE_DE.md')
if not p.exists() or not p.read_text().strip():
    p.write_text('''# Hilfe / BlackHole Routing\n\nDiscord Output -> BlackHole 2ch.\nxPilot Headset/Speaker -> BlackHole 16ch.\nAudioDaBitch Output -> echter Kopfhoerer oder Audiointerface.\n\nKein Multi-Output-Geraet mit Kopfhoerer verwenden, sonst laeuft Audio am Limiter vorbei.\nAlle Geraete moeglichst auf 48 kHz setzen.\n''')
# Try to make update tab visibly marked without touching audio engine.
main=Path('Sources/AudioDaBitch/main.swift')
if main.exists():
    s=main.read_text()
    # Keep simple and safe: any Updates tab label gets blue dot prefix for visible update attention.
    s=s.replace('addTab("Updates ●", updatesView())','addTab("🔵 Updates", updatesView())')
    s=s.replace('addTab("Updates", updatesView())','addTab("🔵 Updates", updatesView())')
    # Ensure Changelog tab exists next to Updates if absent.
    if 'addTab("Changelog"' not in s and 'updatesView())' in s:
        s=s.replace('addTab("🔵 Updates", updatesView())', 'addTab("🔵 Updates", updatesView()); addTab("Changelog", textView(changeText, loadResource("CHANGELOG", fallback: fallbackChangelog())))')
    main.write_text(s)
PY
# .gitignore hygiene
cat >> .gitignore <<'EOF'
# AudioDaBitch local artifacts
build/
dist/
*.pyc
__pycache__/
.DS_Store
EOF
# Install this developer tool into repo tools folder as source of truth
mkdir -p tools
APP_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
rm -rf "tools/AudioDaBitch Developer Tool.app"
cp -R "$APP_ROOT" "tools/AudioDaBitch Developer Tool.app"
# Try to generate app icon if iconutil is available
if command -v iconutil >/dev/null 2>&1; then
  iconutil -c icns "tools/AudioDaBitch Developer Tool.app/Contents/Resources/icon.iconset" -o "tools/AudioDaBitch Developer Tool.app/Contents/Resources/DevToolIcon.icns" || true
fi
clean_caches
echo "Patch 0.5.7 angewendet. Audio-Engine wurde nicht inhaltlich geaendert."
echo "Naechster Schritt: Build-Check."
