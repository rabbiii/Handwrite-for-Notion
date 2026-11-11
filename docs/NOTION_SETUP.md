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

## 4. Upload a disposable note

1. Write a short note and tap **Save**. Confirm **Saved on this iPad**.
2. Leave **PDF** selected to upload all pages in one ordered document. **PNG** sync supports a single-page note only; for multiple pages choose PDF. Local **Export → PNG · all pages** remains available and creates a separate image for each page.
3. Check the destination name, then tap **Sync to Notion** once. The app disables overlapping actions and displays progress.
4. Wait for the success message, then open the destination in Notion. Open its PDF/image attachment and inspect the handwriting.
5. Add another stroke and sync again using the same format and destination. The app should replace its existing block. Syncing again without local changes should report that it is already synced.

The app pins **`Notion-Version: 2026-03-11`**, which is supported by the retrieved official SDK. It reads the workspace's reported file-upload allowance and caps this implementation at **20 MiB per file** because it uses single-part upload. If the workspace allowance is missing, it falls back to **5 MiB**. This conservative fallback is not a claim that every free account has a permanently fixed entitlement. PNG sync tries smaller render scales while retaining a 768 × 1024 minimum; an over-limit export produces an error instead of dropping pages. Split a large notebook into smaller notes or export it locally if necessary.

## What repeated sync changes

- The app tracks the note, destination, format, and returned Notion block ID. It also places a stable PencilNotes identifier in the block caption to help find a prior upload. Keep that identifier intact for reliable recovery.
- Editing and syncing the same note to the same destination in the same format updates that format's block.
- Changing from PDF to PNG, or changing the destination, preserves the older block. It searches the selected page for the matching note-and-format marker before creating a block. Switching back can therefore find and update the older matching block.
- Removing the local note does not delete the Notion copy. Restoring an editable backup creates a separate local note with a new identity and cleared sync linkage.
- Sync does not continuously mirror remote edits. If you move or delete a Notion block, PencilNotes will not silently infer where you intended it to go.

## Retry and repair

**No internet:** Local notes, saving, and export work offline. Restore connectivity and retry sync. Inspect Notion if the connection failed near the end of an upload; a lost response can leave a successful remote write.

**Uncertain append:** If the app says a previous sync may have reached Notion, use the **original destination and format**, wait, and retry so it can search for the existing block. If it still cannot reconcile, open that original page in Notion and look for the attachment and its PencilNotes caption. Only after verifying that no corresponding block exists, use the note's **••• → Resolve uncertain sync → I checked: no block exists**, then retry. Do not clear this state simply to dismiss an error. Delayed visibility or an altered caption can otherwise lead to duplicates; exactly-once delivery is not guaranteed.

**Deleted or moved block:** If a linked block was deleted or moved and a subsequent update fails, first inspect Notion and confirm the intended destination. Use the note's **••• → Reset Notion link**, then sync. The next sync searches the selected page and updates a matching block or creates one if absent. A block moved elsewhere remains there. Do not use this action to work around missing page permission; restore access first.

**Invalid token / 401:** Reopen Notion Settings, enter a valid internal integration token, and reconnect. Check that the integration has not been revoked.

**Permission error / 403 or 404:** Recheck the workspace, page connection, and Read/Insert/Update capabilities. A 404 can mean a page/block is inaccessible, not only that it was deleted. Do not repeatedly reset the link without resolving permissions.

**No search results:** Confirm the page is connected to this integration, wait for indexing, try its exact title, and use Refresh. Page search is title search over accessible results, not an enumeration of your whole workspace or handwriting search.

**File limit / 400:** Read the displayed size/limit error. Use PDF for a multipage note; reduce the content per notebook if the resulting file is too large. Local exports and editable backups are separate from upload size limits.

**Rate limit / 429:** Wait at least the retry interval displayed in the error before trying again. The app does not automatically replay failed writes. Avoid repeatedly reconnecting or tapping sync; retry persistent errors later.

Continue with the [device acceptance checklist](ACCEPTANCE_TESTS.md) before using the app for important notes.
