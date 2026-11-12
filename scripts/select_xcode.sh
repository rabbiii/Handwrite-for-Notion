#!/usr/bin/env bash
set -euo pipefail
pencil_xcode="$(python3 - <<'PY'
from pathlib import Path
import re
versions=[]
for path in Path('/Applications').glob('Xcode_*.app'):
    m=re.fullmatch(r'Xcode_(\d+(?:\.\d+)*)\.app',path.name)
    if m:
        version=tuple(map(int,m[1].split('.')))
        if version[0] >= 26: versions.append((version,str(path)))
assert versions,'Xcode 26 or newer is required for native Liquid Glass'
print(max(versions)[1])
PY
)"
sudo xcode-select --switch "$pencil_xcode/Contents/Developer"
xcodebuild -version
