#!/usr/bin/env bash
# Build on a Mac/Xcode runner. AltStore signs the output on the user's PC.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]] || ! command -v xcodebuild >/dev/null 2>&1; then
  echo 'This build needs macOS with Xcode. Use the Build iPad app GitHub Actions workflow.' >&2
  exit 1
fi
python3 scripts/generate_xcode_project.py
pencil_build="$PWD/.build/ios-sideload"
pencil_payload="$pencil_build/staging/Payload"
mkdir -p "$pencil_payload" dist
xcodebuild -version
xcodebuild -project MacBuild/PencilNotes.xcodeproj -scheme PencilNotes \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$pencil_build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
pencil_app="$pencil_build/DerivedData/Build/Products/Release-iphoneos/PencilNotes.app"
test -x "$pencil_app/PencilNotes"
# ditto replaces existing contents without deleting unrelated staging files.
ditto "$pencil_app" "$pencil_payload/PencilNotes.app"
ditto -c -k --keepParent "$pencil_payload" "$PWD/dist/PencilNotes-unsigned.ipa"
python3 - <<'PY'
from pathlib import Path
import zipfile
import hashlib
archive = Path('dist/PencilNotes-unsigned.ipa')
with zipfile.ZipFile(archive) as bundle:
    assert bundle.testzip() is None
    assert 'Payload/PencilNotes.app/Info.plist' in bundle.namelist()
    assert 'Payload/PencilNotes.app/PencilNotes' in bundle.namelist()
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
Path('dist/PencilNotes-unsigned.ipa.sha256').write_text(f'{digest}  {archive.name}\n')
print(f'Built {archive}. UNSIGNED: use AltStore/AltServer to sign and install it.')
PY
