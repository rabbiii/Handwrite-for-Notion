#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate_xcode_project.py
pencil_simulator="$(xcrun simctl list devices available -j | python3 -c 'import json,sys,re; d=json.load(sys.stdin); devices=[(tuple(map(int,re.findall(r"[0-9]+",runtime))),v) for runtime,values in d["devices"].items() if "iOS" in runtime for v in values if "iPad" in v["name"]]; assert devices,"No iPad simulator is installed"; print(max(devices,key=lambda item:item[0])[1]["udid"])')"
mkdir -p .build/ios-tests dist/UI-Previews
set +e
xcodebuild test -project MacBuild/PencilNotes.xcodeproj -scheme PencilNotes \
  -configuration Debug -destination "platform=iOS Simulator,id=$pencil_simulator" \
  -parallel-testing-enabled NO -resultBundlePath .build/ios-tests/Results.xcresult \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tee .build/ios-tests/build.log
pencil_status=${PIPESTATUS[0]}
set -e
python3 - <<'PY'
from pathlib import Path
lines=Path('.build/ios-tests/build.log').read_text(errors='replace').splitlines()
errors=[line for line in lines if 'error:' in line or 'failed -' in line]
for error in errors[:20]:
    print('::error::'+error.replace('%','%25').replace('\r','%0D').replace('\n','%0A'))
PY
if [[ -d .build/ios-tests/Results.xcresult ]]; then
  xcrun xcresulttool export attachments --path .build/ios-tests/Results.xcresult --output-path dist/UI-Previews || true
fi
exit "$pencil_status"
