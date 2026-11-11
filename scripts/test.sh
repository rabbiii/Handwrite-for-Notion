#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "${SWIFT_BIN:-}" ]]; then
  pencil_swift="$SWIFT_BIN"
elif command -v swift >/dev/null 2>&1; then
  pencil_swift="$(command -v swift)"
elif [[ -x /workspace/toolchains/swift-6.2.3-RELEASE-ubuntu24.04/usr/bin/swift ]]; then
  pencil_swift=/workspace/toolchains/swift-6.2.3-RELEASE-ubuntu24.04/usr/bin/swift
else
  echo 'Install Swift 5.9+ or set SWIFT_BIN to your Swift executable.' >&2
  exit 1
fi
pencil_cache="$PWD/.build/local-cache"
mkdir -p "$pencil_cache/clang" "$pencil_cache/swiftpm" "$pencil_cache/config" "$pencil_cache/security"
export CLANG_MODULE_CACHE_PATH="$pencil_cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$pencil_cache/clang"
"$pencil_swift" test --jobs 4 --cache-path "$pencil_cache/swiftpm" --config-path "$pencil_cache/config" --security-path "$pencil_cache/security"
"$(dirname "$pencil_swift")/swiftc" -frontend -parse PencilNotes.swiftpm/App/*.swift PencilNotes.swiftpm/Core/*.swift
echo 'Portable tests and Swift source syntax checks passed. Apple SDK/device checks remain separate.'
