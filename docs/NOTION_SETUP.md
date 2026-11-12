# Connect PencilNotes to your Notion workspace

PencilNotes uses a **personal internal integration** and sends exported PNG/PDF files directly to the official Notion API. There is no application server or recurring PencilNotes subscription. Keep the editable original in PencilNotes and export `.pencilnote` backups separately: the Notion attachment is a rendered copy, not editable PencilKit ink.

The current API contracts were checked against Notion's official SDK. No live token or workspace was supplied here, and the Notion settings website could not be fetched from the cloud environment. The steps below use Notion's established settings flow; current UI labels may vary. See [API research and sources](NOTION_API_RESEARCH.md) for the evidence boundary.

## 1. Create your personal internal integration

1. On your iPad, open Safari and sign in to the Notion account that owns or administers the intended workspace.
2. Open [Notion integration settings](https://www.notion.so/profile/integrations). If the page redirects, use the integrations/developer-connections area in your account settings.
3. Choose **New integration** (or the equivalent create action).
4. Name it **PencilNotes**, choose the intended workspace, and choose **Internal** if an integration type is offered. Create/save it. A public integration, OAuth redirect URL, paid hosting account, and App Store publication are not required for this personal setup.
5. In its **Capabilities** settings, enable **Read content**, **Insert content**, and **Update content**. Read is needed to find pages and reconcile previous uploads; Insert creates the first attachment block; Update replaces the app's existing block on later syncs. Save the capability changes.
6. Choose **No user information** if that capability option is shown. PencilNotes does not need user email addresses, comments, or unrelated permissions.
7. Open the integration's **Configuration** or secret/token section. Reveal and copy its **Internal Integration Secret** / token. Do not put it in a Swift file, note title, chat message, screenshot, or repository.

If your workspace does not permit you to create internal integrations or add connections, its owner/admin must grant that permission or create the integration. A token from another workspace does not automatically grant access to this one.

## 2. Give the integration access to a destination page

1. In Notion, create a disposable page named **PencilNotes Test** in the same workspace.
2. Open that page's **•••** menu.
3. Find **Connections**, **Add connections**, or **Connect to**, then choose **PencilNotes**, your integration's name.
4. Confirm the access prompt. If Notion instead provides an access picker in the integration's settings, grant this test page there and verify the connection on the page.
5. Repeat this for other intended destination pages after the test succeeds. Do not grant access to the whole workspace just to make a test page appear.

Both the integration's capabilities and page-level access matter. A page visible to you in Notion may remain invisible to the integration. Search results also depend on Notion's indexing, so newly connected pages may take time to appear.

## 3. Connect inside PencilNotes

1. Run PencilNotes in Swift Playground.
2. Tap the gear button in the notes sidebar to open **Notion Settings**.
3. Paste the token into **Internal integration token**. The field masks its contents.
4. Tap **Connect Notion**. Wait for **Connected** and the workspace/integration name. Successful verification stores the token in the app's own Keychain and clears the entry field.
5. Tap **Done**. Open or create a note, then tap **Choose Notion Page**.
6. Search for **PencilNotes Test** and select the result. The app remembers the selection for that note.

On subsequent launches, **Saved connection · verify online in Settings** means a credential was recovered from Keychain; it is not a fresh network test. Use **Verify Connection** to check it. **Disconnect** removes the app's stored token. To rotate/revoke a token, do so in Notion as well; disconnecting this app alone does not revoke the server-side credential.

## 4. Sync a disposable note

1. Write a short note and tap Save. Confirm the local save status.
2. In the floating top toolbar, choose the Notion destination and tap **Sync to Notion**. Swipe horizontally through the toolbar if a control is outside the visible area.
3. Open the destination in Notion and inspect its single image. Its height follows the lowest stroke, and its background is `#191919` to blend with Notion dark mode. Ink colors are preserved rather than inverted; choose suitable ink colors for the image background.
4. Add another stroke and sync again. The app updates its existing image block instead of appending another image.
5. Turn on **Auto sync** beside Sync. A request starts half a second after canvas activity finishes; network transfer can take longer. Drawing remains available while uploading. Further edits are combined into a later update of the same block.

There is no format picker or PDF export. Existing older attachments in Notion are not automatically deleted. Notes upgraded from older paged notebooks keep all editable strokes, joined in order into one continuous canvas.

## Upload limits and recovery

The client uses the supported `Notion-Version: 2026-03-11` contract and checks the workspace's reported file allowance. Single-part uploads are capped at 20 MiB, with a conservative 5 MiB fallback if Notion omits the allowance. Long canvases are downsampled within raster-memory and image-dimension bounds. If a safe image cannot fit the allowance, the app gives a descriptive error and keeps the editable source.

Auto Sync pauses after a network, credential, or permission failure. Restore access and tap Sync, or switch Auto Sync off and on. It operates while the app is active; background execution is not guaranteed by iPadOS.

A lost append response can be ambiguous. The app records a stable caption marker before appending and searches for it on retry. Keep that marker in the Notion image caption. If a pending block cannot be found, wait and inspect the original destination before using **Note actions → Resolve uncertain sync**. Never reset an uncertain operation merely to dismiss its error.

If a previously linked block was deleted or moved, restore the intended destination/permissions and use **Reset Notion link**. A fresh search checks the selected page before creating a replacement. A block moved elsewhere is not deleted by the app.

- **401:** reconnect using a valid internal integration token.
- **403/404:** check integration capabilities and page connections; inaccessible pages can look missing.
- **429:** wait the Retry-After interval displayed before manually retrying. Writes are not automatically replayed.
- **No search results:** share the page with the integration, allow indexing time, and refresh title search.
- **Offline:** local notes and editable backups keep working. Reconnect and retry sync deliberately.

Deleting a local note leaves its remote image intact. Restored backups receive a new local identity and cleared destination/sync links. Export editable backups regularly; Notion images do not contain the original PencilKit strokes.
