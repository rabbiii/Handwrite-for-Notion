# Run PencilNotes on your iPad

## What can be verified here

PencilNotes is designed as an **iPad app playground**, using SwiftUI, PencilKit, UIKit, Foundation/URLSession, and Security/Keychain. Its app deployment target is iPadOS 17 or later. It needs no paid library, server, OCR service, or recurring subscription. Notion receives the exported document; editable PencilKit strokes remain in the app's local storage.

This project was created in a Linux environment. **An Apple SDK build, opening the package in Swift Playground, Pencil input, export rendering, Keychain persistence, and the actual iPad UI have not been tested here.** Linux cannot substitute for those checks. Use the [device acceptance checklist](ACCEPTANCE_TESTS.md) before trusting the app with your only copy of important notes.

Apple's current website, documentation, and App Store pages could not be retrieved from this environment: the network proxy denied connections to `www.apple.com`, `support.apple.com`, `developer.apple.com`, and `apps.apple.com`. Accordingly, this guide does **not** assert a verified current Swift Playground version, current App Store operating-system requirement, or exact current toolbar wording. The primary-source links below are supplied for checking on your iPad. UI labels can vary by release.

## Feasibility and boundaries

| Requirement | Implementation and iPad path | Verification still needed |
| --- | --- | --- |
| Apple Pencil canvas | `PKCanvasView` inside SwiftUI with native PencilKit tools. UIKit and PencilKit are platform frameworks, not downloaded packages. | Apple Pencil strokes, tool picker, finger scrolling, undo/redo on the actual device. |
| Editable offline notes | Store original `PKDrawing` representations in the app container, separately from exported documents. | Force quit/relaunch, interrupted saves, device storage errors. |
| PNG/PDF export | UIKit image/PDF renderers; iPad share sheet to Files. | Full-page rendering and share-sheet presentation on iPad. |
| Notion connection | Personal internal integration token stored in the app's own Keychain. HTTPS via URLSession. | Device Keychain behavior and a real user's authorized Notion connection. |
| Destination selection | Paginated Notion page search. The integration sees only pages it is allowed to access. | A workspace with shared pages, including pagination. |
| Sync | Official Notion upload endpoints and image/PDF blocks; no application backend. | Live Notion uploads and retry behavior against an authorized workspace. |

Running in Swift Playground is the intended personal-use path. This guide does not promise a standalone home-screen installation or indefinite distribution outside Swift Playground. App Store/TestFlight distribution has separate signing, membership, and review requirements and is not required for this project. App-owned Keychain items do not require Keychain Sharing, iCloud, or another paid service. Exporting a copy into an iCloud Drive location through Files does not add an iCloud entitlement to the app.

## Before opening the project

1. In iPad **Settings → General → About**, check that your iPad runs iPadOS 17 or later.
2. Open the App Store listing for **Swift Playground** and install its latest version compatible with your device. The App Store's current requirement takes precedence over this project's minimum deployment target.
3. Keep a copy of the delivered archive in Files. App source archives and handwritten-note backups are different things: the source archive does not contain notes you create later.
4. Keep at least one important-note backup outside the app before deleting the app, deleting its playground, or changing its application bundle identifier. Such changes may create a new app data container; Keychain and file persistence should not be assumed across those changes.

## Preferred route: open the app playground package

1. Download the delivered PencilNotes archive to **Files** on the iPad. For the first run, keep a local copy under **On My iPad** (use the Swift Playground folder if offered). If it arrives as a ZIP file, tap it in Files to extract it. Avoid running directly from a ZIP preview or a third-party file-provider preview.
2. Locate the **`PencilNotes.swiftpm`** item in the extracted folder. Keep the complete package together; do not open `Package.swift` as though it were a standalone Swift script.
3. Tap the `PencilNotes.swiftpm` item. If Files does not open it in Swift Playground directly, use its Share action and choose Swift Playground if offered, or use Swift Playground's document browser to open it from Files.
4. Open the project in Swift Playground. Use the triangle **Run** control to build and run the app. Allow the first build to complete.
5. If the editor reports a problem in `Package.swift`, use the manual route below. If the runner shows **Prewarm failed** and a **CurrentUser.txt** permission error, follow the recovery steps below before changing app source.
6. Create a disposable note and verify local writing, saving, reopening, and export before entering your Notion token.

Package-opening behavior can depend on Files providers and the installed Swift Playground release. The fallback below deliberately uses the manifest generated by your own installed version.

## Recovery: “Prewarm failed” / “CurrentUser.txt” permission error

This launch failure was reported on an iPad when running the imported package. PencilNotes does not create or reference `CurrentUser.txt`; its note files live in a `PencilNotes` subfolder. The filename and “prewarm” wording point to Playground's launch setup, but the screenshot alone does not establish the underlying cause. The Finder → Get Info advice is a generic system message, not an iPad action.

The original source ZIP inherited Linux owner-only file modes (`0600`) and omitted explicit directory entries. The packaging script now emits files with `0644` modes and directories with `0755` modes. This removes a portability concern; it is **not proof** that archive permissions caused the launcher error or that the rebuilt ZIP fixes it.

1. Tap **Stop**. Keep the existing project; do not delete notes or the Swift Playground app as a troubleshooting step.
2. Download the rebuilt ZIP and extract it into a new local folder under **Files → On My iPad**. Open that newly extracted `PencilNotes.swiftpm` in Swift Playground and try Run once.
3. If the same error appears, return to Swift Playground's project browser and create a **new App** named **PencilNotes Local**. Keep the template's generated project settings and manifest. **Run the untouched template first**, before copying any PencilNotes code. This separates a general runner problem from one associated with the imported project.
4. If the untouched template runs, stop it. Open the delivered `PencilNotes-All.swift` as text and copy its complete contents. In the new App, replace the entire generated `@main` file (usually `MyApp.swift`) with that text, then delete the template's unused `ContentView.swift`. Do not add the split source files or either delivered `Package.swift`. Run again. This uses a project and app data container created by your installed Playground version.
5. If even the untouched template fails with the same error, stop it, close and reopen Swift Playground, and check for an update in the App Store. A device restart is a further runner troubleshooting step. Record your iPadOS and Swift Playground versions and whether the template runs; modifying PencilNotes note-storage code cannot establish why the template's launch failed.

**Delete App Data & Restart** explicitly erases that app's local data. Use it only if the affected app has no notes you need, or after exporting and checking editable backups. Do not use it as the default remedy for a project with existing notes. A fresh template is the non-destructive diagnostic route.

## Fallback: create a new App and add the source files

The ZIP also includes **`PencilNotes-All.swift`**, containing the same app/core code in one file. For fewer paste steps, create a new App template, replace the generated `@main` file's entire contents with that file, remove the generated `ContentView.swift`, and keep the template's own manifest. Do not also add the split App/Core files. The combined file still needs the on-device compilation and feature checks below.

1. Open Swift Playground and return to its project/document browser.
2. Choose the option to create a new **App** playground (the **App** template). Do not choose a blank playground book or a command-line Swift package.
3. Name the new app **PencilNotes**. Open it, then reveal the code/file sidebar using the sidebar control.
4. Locate the generated Swift file that contains `@main` (often named `MyApp.swift`) and the generated `ContentView.swift`.
5. Replace the generated app-entry file's complete contents with **`PencilNotes.swiftpm/App/PencilNotesApp.swift`**, which contains PencilNotes's `@main` application declaration. There must be **exactly one `@main` declaration** across the app's compiled Swift files.
6. Add each other delivered app `.swift` source file from **both `PencilNotes.swiftpm/App/` and `PencilNotes.swiftpm/Core/`** to the App project. Use the sidebar's add/new-file action and choose a Swift source file, then paste that file's entire contents. Preserve the filenames and include every source file, including shared models and networking files. If a delivered source is named `ContentView.swift`, replace the generated `ContentView.swift` instead of creating a duplicate type. This app has no `ContentView.swift`, so remove the unused generated `ContentView.swift`.
7. Do **not** add the repository's test files, Linux validation package manifest, or documentation as Swift app source. Do **not** paste `Package.swift` into a source file. Keep the App template's generated manifest for this fallback route.
8. Set the app's deployment target to iPadOS 17 or later if the settings expose it. A higher target supported by your device is acceptable. Keep a stable, unique bundle identifier (for example, your own reverse-domain identifier ending in `.PencilNotes`).
9. No third-party package dependencies, external servers, iCloud capability, App Groups, Keychain Sharing, camera, microphone, or photo-library entitlement is required. Standard HTTPS calls do not require an App Transport Security exception. Save exports using the share sheet and **Save to Files**.
10. Press the triangle Run control. If compilation fails, read the first compiler diagnostic rather than the last cascading error. Compare your project file list with the delivered app package and check for truncated pastes or duplicate declarations.

## Source-file checklist for the manual route

The delivered app currently has **12 Swift source files**. They are all compiled into the same App module; folder groups are optional when adding them manually.

| Location in the package | Files to include |
| --- | --- |
| `App/` | `PencilNotesApp.swift`, `AppModel.swift`, `NotebookView.swift`, `NoteEditorView.swift`, `NotionSettingsView.swift`, `InkCanvas.swift`, `NoteExporter.swift`, `KeychainStore.swift` |
| `Core/` | `Models.swift`, `NoteRepository.swift`, `NotionClient.swift`, `SyncCoordinator.swift` |

`PencilNotes.swiftpm/Package.swift` is the app-playground manifest. The **repository-root `Package.swift` is a different, Linux-testable library package**, and `Tests/` contains its tests. Neither belongs in a manually created iPad App's source list. Keep the generated App manifest in the fallback route.

## First run and safe progression

1. Create a note and give it a recognizable title. Draw several strokes, including an equation and a diagram near the lower edge of a page.
2. Check the pen, eraser, and undo/redo controls. Distinguish scrolling with a finger from writing with Apple Pencil using the app's drawing setting.
3. Save, leave the editor, reopen the note, and erase an old stroke. Successful erasing confirms editable strokes were restored rather than a flattened image.
4. Close and reopen the running app. Confirm the note remains. Test this with disposable material first.
5. Export PNG and PDF, choose **Save to Files**, and open each file from Files. Inspect the bottom and right edges and all PDF pages.
6. Open Notion settings and follow [Notion setup](NOTION_SETUP.md) to create a personal internal integration and grant access to a disposable page. Enter the token only inside the app's secure settings field. Never put the token in source files or share it in chat.
7. Connect, choose the disposable destination page, and sync. Open Notion to inspect the actual attachment. Remember that Notion displays an exported document; editing the original ink remains an iPad operation.
8. Repeat using Airplane Mode to verify readable failure handling and local-note safety. Turn connectivity back on and follow the app's retry guidance, checking the destination page for duplicates.

## Troubleshooting on iPad

- **“No such module AppleProductTypes”**: `AppleProductTypes` belongs to Apple's app-playground manifest tooling. The app package is not a normal Linux/macOS command-line package. Open it as an App in Swift Playground, or use the generated-template fallback. This message on Linux does not demonstrate an iPad source error.
- **`@main` / duplicate `App` / duplicate `ContentView` errors**: remove or replace the template declarations as described above. Keep only the delivered entry point.
- **Missing type or symbol errors**: confirm every delivered app source file was added, including shared model and networking files. Check that no file was pasted incompletely.
- **API unavailable errors**: check both iPadOS and the App's deployment target. Updating Swift Playground may be necessary to supply a sufficiently recent Apple SDK.
- **PencilKit tools do not appear**: tap the drawing surface and check the app is foregrounded. Test on the physical iPad with the Pencil paired; a Linux test cannot verify tool-picker behavior.
- **Finger draws instead of scrolling**: check the app's Pencil/finger input option. Test navigation with a finger and ink with Apple Pencil before relying on this distinction.
- **Share sheet does not appear or export is unreadable**: use a small disposable drawing first, then capture the exact device error. Keep the original note; an export failure is not a reason to delete it.
- **Notes seem to disappear after project changes**: confirm you opened the same App project with the same bundle identifier. Do not delete the previous project or app container while investigating.
- **Notion rejects a token or cannot find a page**: ensure it is an internal integration secret, then add the integration to the target page's connections and enable the integration capabilities required by the app. Search does not enumerate all workspace pages.
- **Notion file-size error**: use the app's size warning and reduce the number/complexity of pages or choose a smaller supported export. A larger workspace upload allowance should not be assumed for a free account.

## Primary-source references

These links identify the authoritative APIs and product documentation; as noted above, their current content was not retrievable in the build environment.

- Apple, [Swift Playground product overview](https://www.apple.com/swift/playgrounds/).
- Apple, [Swift Playground for iPad user guide](https://support.apple.com/guide/playgrounds-ipad/welcome/ipados).
- Apple, [Swift Playground App Store listing](https://apps.apple.com/us/app/swift-playgrounds/id908519492) — verify the current version and minimum iPadOS here.
- Apple Developer, [PencilKit](https://developer.apple.com/documentation/pencilkit), [PKCanvasView](https://developer.apple.com/documentation/pencilkit/pkcanvasview), and [PKDrawing](https://developer.apple.com/documentation/pencilkit/pkdrawing).
- Apple Developer, [UIViewRepresentable](https://developer.apple.com/documentation/swiftui/uiviewrepresentable).
- Apple Developer, [UIGraphicsImageRenderer](https://developer.apple.com/documentation/uikit/uigraphicsimagerenderer), [UIGraphicsPDFRenderer](https://developer.apple.com/documentation/uikit/uigraphicspdfrenderer), and [UIActivityViewController](https://developer.apple.com/documentation/uikit/uiactivityviewcontroller).
- Apple Developer, [Keychain services](https://developer.apple.com/documentation/security/keychain_services) and [URLSession](https://developer.apple.com/documentation/foundation/urlsession).
- Apple Developer, [Choosing a membership](https://developer.apple.com/support/compare-memberships/) — distribution and membership are separate from running an App inside Swift Playground.
