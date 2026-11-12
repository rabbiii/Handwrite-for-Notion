# PencilNotes

A native iPad handwriting notebook with editable PencilKit ink, local storage, and one-way image sync to Notion.

## Notebook

The drawing surface uses Apple's public PencilKit canvas and native tool picker. It has a fixed logical width and grows vertically as you write or scroll. Pen, pencil, marker, eraser, selection/lasso, ruler, and Pencil input are supplied by PencilKit. Apple's Notes app itself is not an embeddable framework.

The surface follows the system's light/dark appearance. Floating, horizontally scrollable controls sit over the drawing: Undo, Redo, Finger drawing, Clear Canvas, Save, Export, Notion destination, Sync, Auto Sync, Settings, and note actions. There is no app-owned bottom utility bar or page navigator. The native PencilKit tool palette retains its system docking behavior. Liquid Glass is used on iPadOS 26 and later, with a material fallback for earlier systems.

## Images and Notion

Each sync sends one PNG image whose height follows the lowest stroke. The background is `#191919`, chosen to blend with Notion's default dark page background. Original stroke colors are rendered unchanged, so black ink remains black. Notion themes can change independently of this app.

The image normally keeps the canvas's fixed width. Off-canvas ink moved with the lasso is included and fitted horizontally. Extremely long drawings are downsampled to bound rendering memory; a clear error is shown if safe rendering or Notion's file-size limit cannot be met. No strokes are silently dropped. There is no PDF choice.

The app updates its existing image block after edits. Notion receives a rendered image; original editable strokes stay in the app. A personal Notion integration token is stored in Keychain. Follow [Notion setup](docs/NOTION_SETUP.md) for permissions and page access.

## Autosync and local safety

Auto Sync is optional and initially off. When enabled, it waits 0.5 seconds after drawing/erasing/undo/scroll interaction finishes. If a previous upload is still running, edits are coalesced into the next upload. Drawing stays available during sync; network completion merges only remote metadata, preserving newer local ink. The delay begins a request rather than guaranteeing that a network upload completes within 0.5 seconds.

Autosync requires a saved connection, a destination, internet, and an active app. A network or permission error pauses automatic attempts; tap Sync to retry or turn Auto Sync off and on. The app never blindly retries an uncertain block append. The note menu offers reconciliation/reset actions with explicit inspection instructions.

Local strokes are saved after a short pause and on navigation/backgrounding. Notes use atomic writes and retain a previous readable version. Export an Editable Backup regularly to Files/iCloud Drive, particularly before updating or changing app identity. Restoring a backup creates a separate note. Existing paged notes are migrated into one continuous drawing with editable strokes in their original order.

## Source and development

- `PencilNotes.swiftpm/App/`: SwiftUI, native canvas, image renderer, and Keychain.
- `PencilNotes.swiftpm/Core/`: models, persistence, geometry, debounce, and Notion requests/sync.
- `PencilNotes.swiftpm/Resources/`: app icon and monochrome accent assets.
- `MacBuild/PencilNotes.xcodeproj`: standalone iPad app target.
- `Tests/`: portable tests plus iPad simulator drawing/export checks.

With Swift installed, run `bash scripts/test.sh`. Native builds and simulator checks require Xcode 26 or newer. `python3 scripts/generate_xcode_project.py` regenerates source/resource references when files change. Keep the application bundle identifier stable for personal updates.

The portable tests exercise storage, geometry, timing, and mocked Notion behavior. Simulator tests exercise PencilKit migration, clear/undo, PNG colors/dimensions, storage reopening, and light/dark editor rendering. Physical Pencil behavior, SideStore installation, live Notion permissions/uploads, and perceptual glass appearance on an actual iPad require device checks.
