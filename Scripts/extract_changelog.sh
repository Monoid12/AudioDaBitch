#!/usr/bin/env bash
set -euo pipefail
VERSION="${1#v}"
awk -v ver="$VERSION" '
  $0 ~ "^## \\[" ver "\\]" {flag=1; print; next}
  flag && $0 ~ /^## \[/ {exit}
  flag {print}
' CHANGELOG.md
