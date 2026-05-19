#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import re
version = "0.5.0"
text = Path("CHANGELOG.md").read_text(encoding="utf-8")
pat = re.compile(r"^## \[?" + re.escape(version) + r"\]?.*?$", re.M)
m = pat.search(text)
if not m:
    print(text)
    raise SystemExit(0)
start = m.start()
n = re.search(r"^## ", text[m.end():], re.M)
end = m.end() + n.start() if n else len(text)
print(text[start:end].strip())
