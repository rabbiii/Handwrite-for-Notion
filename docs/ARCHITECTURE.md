# Contributing

The app uses SwiftUI and PencilKit. `PencilNotes.swiftpm/App` contains the interface and platform services; `Core` contains storage, models, and Notion sync. Tests include portable core checks and native iPad simulator checks.

Run `bash scripts/test.sh` with Swift installed. Native checks require macOS and Xcode 26 or newer; run `bash scripts/test_ios.sh`. Generate the Xcode project with `python3 scripts/generate_xcode_project.py` after adding source files.

The GitHub Actions workflow tests the project, builds an unsigned IPA, and publishes a release. Signing is handled separately by the installer. Never commit credentials or personal note data.

Keep migrations backward compatible. Preserve original files on storage failures, and merge sync metadata without overwriting newer handwriting. Include focused tests for persistence and synchronization changes.
