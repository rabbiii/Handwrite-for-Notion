# Notebook architecture

## Editable surface and storage

The app uses a native `PKCanvasView`, native PencilKit tool picker, and original `PKDrawing` bytes. Logical width is fixed at 768 points; the displayed scale adapts to the editor width. Content height grows ahead of the viewport and the lowest stroke, so there is no page boundary or bottom utility section. Finger navigation and optional finger drawing are separate input policies; native tools supply erasing, selection, ruler, and ink choices.

Theme colors follow the system. SwiftUI controls float above the canvas, with real Liquid Glass on supported systems and a material fallback on older ones. The system PencilKit palette retains its own docking behavior. Apple Notes' private implementation is not used.

Local files remain versioned atomic `.pencilnote` envelopes. The legacy `pages` field is retained for compatibility, but current notes contain one drawing and `canvasVersion: 2`. Legacy notes are migrated by appending transformed original strokes vertically in order, then saving atomically. A previous file version is retained by the repository. No image flattening is used for migration or editing.

Autosave flushes dirty note data after 450 ms of inactivity, during navigation, and when leaving the active scene. A storage error prevents discarding unsaved state and is displayed explicitly. Editable backups contain metadata and strokes but no credential. Import creates a new identity and clears remote links.

## Image output

Output is a single PNG with a fixed logical width and a height derived from ink bounds plus bottom padding. Empty notes receive a small blank image. Scroll position and the amount of empty canvas do not enlarge the output. Off-width or negative-coordinate ink, including old lasso-moved strokes, is included and fitted rather than cropped.

The background is explicit sRGB `#191919`, chosen for Notion's default dark page. Original ink colors are preserved. The renderer bounds pixel area and maximum dimension; long images are downsampled, and unsafe/extreme cases fail with an actionable message. Lower render scales are attempted if the PNG exceeds the workspace's upload allowance. There is no PDF output in the editor or exporter; legacy format values remain decodable for old note metadata.

Encoding for sync runs on a separate actor with a captured appearance context, so rasterizing a tall image does not occupy the Pencil input thread. Image export does not replace the original drawing.

## Network and autosync

A personal internal integration token is verified before replacement and stored in app-owned Keychain with device-only, unlocked accessibility. Only the user's selected image/title and the necessary API requests go to Notion. Disconnect removes the stored token. Tokens never appear in notes, backups, source, or UI logs.

The Notion client handles paginated search/child lookup, actual account upload limits, single-part create/send, and image block append/update. It spaces requests and reports server retry guidance. Mutations are not automatically replayed.

Auto Sync is optional. A main-actor debounce waits 0.5 seconds after the last completed tool, scroll, or edit activity. Only one sync runs at a time. More edits are queued/coalesced; a debounce cancellation never cancels an in-flight write. Scene inactivity cancels timers, and pending work can resume on activation. Errors pause automatic attempts until explicit retry or re-enabling the toggle.

Each upload uses an immutable note snapshot. Completion merges only remote sync metadata into the latest local note and persists that latest content. Thus new strokes cannot be overwritten by an older upload result. If current content differs from the uploaded revision, another update is queued when the canvas is idle.

Before a new image block is appended, its stable marker is saved durably. An uncertain response leaves that marker for reconciliation; retry searches existing destination children and refuses a blind duplicate append. Existing image block IDs are reused for subsequent updates. Changing destinations preserves older remote content. Imported backups receive a separate identity.

## Checks

Portable checks cover original storage behavior and API contracts, plus debounce cancellation/timing, export geometry, raster bounds, and merging older upload metadata with newer ink. Native iPad simulator checks exercise actual PencilKit migration, variable-height PNG rendering/background/ink colors, saved strokes, clear/undo/redo, delayed-network concurrent editing, and light/dark editor rendering. Physical Apple Pencil feel and live Notion behavior remain device acceptance checks.
