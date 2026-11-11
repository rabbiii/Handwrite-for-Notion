# PencilNotes

A personal iPad notebook built with SwiftUI and PencilKit. Write with Apple Pencil, reopen and edit the original strokes, export every page, and send a PDF or PNG to a page in your Notion workspace.

**Start on iPad:** [installation guide](docs/IPAD_SETUP.md) → [Notion connection guide](docs/NOTION_SETUP.md) → [device checklist](docs/ACCEPTANCE_TESTS.md).

The app package is **`PencilNotes.swiftpm`**. The `Package.swift` at the repository root is a separate portable test package; do not open that file as the iPad app.

**Windows alternative:** [build on a GitHub cloud Mac, then install using Windows/AltServer](docs/WINDOWS_INSTALL.md). The `MacBuild` Xcode project and manual GitHub Actions workflow prepare an unsigned IPA for personal sideloading, without Swift Playground. The first successful cloud run is still needed to verify the Apple SDK build. Start by checking AltStore can run on your iPadOS version.

## Implemented

- Native PencilKit pen, pencil, highlighter, eraser, color controls, undo/redo, pinch zoom, and finger navigation. Finger drawing is an explicit option.
- Multiple fixed pages per note; create, rename, save, reopen, and delete notes/pages. Original `PKDrawing` bytes are saved after a short pause and on scene changes, navigation, export, and sync.
- Atomic note writes, previous-version recovery, corrupt-file preservation, explicit save errors, and editable backup export/import. Restored backups get independent identities.
- White-background PNG for every page and ordered multipage PDF. Exports scale to include strokes moved outside the paper with the lasso. PNG sync supports one-page notes; use PDF to sync all pages of a longer note.
- Personal Notion internal integration credentials stored in Keychain. Accessible-page search is paginated and destinations are remembered per note.
- Official Notion file uploads and image/PDF blocks. Changed notes update their saved block. Stable caption markers and durable pending operations protect retries after an uncertain response. Changing format creates or reuses a separate block; earlier-format copies remain in Notion.

No external library, OCR service, application backend, recurring subscription, or App Store distribution is required by this design. Running inside Swift Playground is the intended personal-use route; standalone installation is not promised.

## Validation status

The portable core has been compiled and tested on Linux with Swift 6.2.3. Storage, API contracts with mocked URLSession responses, and sync orchestration are covered by XCTest. See [validation details](docs/VALIDATION.md).

**An iPad build and real-device behavior have not been verified here.** Linux has no Apple SDK, PencilKit, UIKit, Security framework, or iPad simulator. App sources pass Swift syntax parsing, which is not Apple SDK type checking. Live Notion requests require your integration and are not covered by mocked tests. Apple documentation hosts were inaccessible from this cloud environment; the guide identifies the platform details that remain to be checked on-device. Current Notion contracts were checked against the official SDK.

## Repository layout

```text
PencilNotes.swiftpm/
  Package.swift                 iPad App Playground manifest
  App/                          SwiftUI UI, PencilKit, exporters, Keychain
  Core/                         Models, atomic persistence, Notion client, sync
Package.swift                   Portable core test target
Tests/PencilNotesCoreTests/      Storage, protocol, and retry tests
docs/                           Setup, architecture, research, acceptance
scripts/test.sh                 Repeatable portable tests + Swift syntax checks
scripts/package.py              Build a clean ZIP and single-file fallback
```

## Development

With Swift 5.9 or later installed:

```sh
bash scripts/test.sh
python3 scripts/package.py
```

The test script accepts `SWIFT_BIN=/path/to/swift` and uses writable caches inside `.build`. On this prepared cloud machine it also locates the installed Swift 6.2.3 toolchain automatically. It does not fetch dependencies or modify source files.

Packaging produces `dist/PencilNotes-iPad.zip`, containing the app package, documentation, and a combined source fallback for pasting into a new App template if importing the package is unavailable. Keep exactly one `@main` entry point. See the iPad guide before copying files.

## Data and sync behavior

Local `.pencilnote` files contain a versioned JSON envelope with note metadata, page identifiers, original PencilKit bytes, and remote block identifiers. Tokens are absent from these files and from backups. Export a backup to Files/iCloud Drive before deleting or renaming the app project or changing its bundle identity.

Sync is explicit and one-way: the app sends an exported document to `api.notion.com`. Notion cannot edit the original PencilKit strokes. There is no automatic upload, handwriting recognition, analytics, or third-party document hosting. Local notes keep working offline. Notion's limits and page permissions still apply.

The app does not automatically delete remote blocks when a local note is deleted. Its caption contains a stable `PencilNotes:…` identifier; leave that identifier intact so interrupted syncs can find the block. Moving/deleting a remote block can require **Note menu → Reset Notion link**. Uncertain appends require reconciliation or explicit inspection before clearing the pending operation.
