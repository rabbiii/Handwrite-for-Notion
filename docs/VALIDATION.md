# Validation record

Validated on 11 November 2026 (Asia/Dhaka) in the cloud Linux workspace.

## Executed

`./scripts/test.sh` compiled the actual portable core with **Swift 6.2.3** and ran **36 XCTest cases, all passing**:

| Suite | Executed | Failed | Coverage |
| --- | ---: | ---: | --- |
| StorageTests | 11 | 0 | Blank/multipage notes, exact binary stroke-data round trip, atomic replacement recovery, corrupt originals, version/identity checks, size validation, sorting, deletion, backup import. |
| NotionClientTests | 13 | 0 | Version/auth headers, account upload limit, paginated search and block lookup, duplicate page IDs, malformed pagination, multipart payloads, append/update JSON, upload confirmation, offline/permission/rate errors, ambiguous writes. |
| SyncCoordinatorTests | 12 | 0 | Pre-append durable intent, unchanged revision, updating existing blocks, response-loss reconciliation, unresolved-write blocking, failed persistence, format/destination changes, and preservation of pending intent across target changes. |

The API tests use URLProtocol mocks. They execute the real request construction and response handling but do not contact Notion. Storage tests use isolated temporary directories and arbitrary binary payloads; they prove byte preservation, not that PencilKit accepts a particular drawing.

Swift's parser also accepted every app/core `.swift` file. This checks source syntax only; imports and Apple framework types are not resolved by that check. The separately generated single-file fallback is parsed as part of package validation.

The delivery script creates a source-only ZIP, tests ZIP integrity, checks paths, and emits a SHA-256 digest. No dependency cache, local note, or credential is packaged.

## Reported iPad launch failure and packaging follow-up

An iPad launch attempt using the imported package reported **Prewarm failed** with a permission error writing `CurrentUser.txt` in `Documents`. No successful iPad launch has been established by that report. The app source contains no reference to `CurrentUser.txt`; the exact cause of the launcher failure remains unconfirmed.

The archive previously inherited `0600` file modes from the cloud workspace. Packaging now explicitly writes `0644` files and `0755` directories, checks those modes, and verifies every archived file matches its input bytes. Those checks verify the rebuilt delivery, not a fix for the iPad runner. [IPAD_SETUP.md](IPAD_SETUP.md) includes a local-copy retry and a fresh, initially untouched App-template test, with instructions that preserve existing projects and notes.

## GitHub macOS build

[Run 43120058457](https://github.com/rabbiii/Handwrite-for-Notion/actions/runs/43120058457) for commit `1b31caf` completed successfully. The workflow ran the portable tests on macOS, compiled the actual app against Apple’s iPadOS device SDK, packaged the unsigned IPA, validated its ZIP structure and required app binary/plist entries, and uploaded artifact `13899074938` (`PencilNotes-unsigned-iPad`, displayed size 310 KB).

The IPA is unsigned for personal signing with SideStore/AltStore. GitHub artifact downloads require sign-in. The local cloud environment blocks `api.github.com`, so the artifact has not been independently downloaded and inspected here; success and artifact metadata were verified on the GitHub run page.

## Remaining device checks

- App Playground import, personal code signing, or physical iPad installation. Apple SDK compilation passed in the GitHub run above.
- Actual Apple Pencil/finger gestures, eraser, tool picker, undo/redo, rotation, split-view layout, and process lifecycle.
- Rendering/inspection of PNG/PDF output, including off-paper ink, or iPad share-sheet presentation.
- Security.framework/Keychain calls on an iPad or the persistence of an installed playground's app identity.
- Live authenticated Notion search, file upload, block insertion/update, real limits, indexing delay, or external service failures.

These are pending checks in [ACCEPTANCE_TESTS.md](ACCEPTANCE_TESTS.md). No device feature is represented as verified by Linux unit tests.

## External-source verification

The current official Notion SDK source and README were retrieved from its public GitHub repository. They support the selected `2026-03-11` API version and the request contracts implemented here. The exact retrieved source reference is documented in [NOTION_API_RESEARCH.md](NOTION_API_RESEARCH.md).

Apple's website, developer reference, support guide, and App Store listing, plus the Notion developer documentation host, returned HTTP CONNECT 403 through this environment's network policy. Their links are included for on-device reference; their current contents, the latest Swift Playground version, and exact current UI labels were not independently verified. No TLS or signature verification was disabled to work around these restrictions.

The Linux Swift toolchain was downloaded from the official Swift distribution and its detached signature verified against the official Swift release signing key before use. The toolchain cannot compile UIKit/PencilKit code without Apple's SDK.
