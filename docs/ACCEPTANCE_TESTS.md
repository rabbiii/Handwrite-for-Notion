# PencilNotes device acceptance tests

**Status: device checks not run in the Linux build environment.** These are instructions and expected results, not a claim that the iPad build, Apple Pencil, share sheet, Keychain, or live Notion connection has passed. Run them with disposable notes and a disposable authorized Notion page. Record your iPad model, iPadOS version, Swift Playground version, date, and each result as **passed**, **failed**, or **not run**.

Start with [iPad setup](IPAD_SETUP.md). Complete cases 1–6 offline if desired, then follow [Notion setup](NOTION_SETUP.md) for cases 7–10. Keep an editable backup before any destructive test.

## 1. Create, rename, and write with Apple Pencil

- Run the app and tap **New Note**. In the note's **•••** menu, choose **Rename Note**, enter `Physics test`, and save.
- With **Draw with finger** off, write an equation and draw a diagram using Apple Pencil. Put recognizable labels near the top, bottom, left, and right edges of the paper.
- Scroll with a finger and pinch to zoom. Rotate the iPad and, if supported by your setup, resize its window.

**Expected:** The title changes; ink follows the Pencil; finger navigation adds no ink; rotation/resizing does not reset the drawing. A newly created empty note is also valid and can be saved/reopened.

## 2. Pen, eraser, undo/redo, and finger mode

- Use the native PencilKit tool picker to change ink color and width. Draw a distinct stroke, erase it, tap **Undo**, then **Redo**.
- Turn **Draw with finger** on. Draw with one finger, then pan with two fingers and pinch to zoom. Turn it off again and verify one-finger scrolling.
- Switch pages/notes after completing a stroke, then confirm the tool picker still appears on the active canvas.

**Expected:** Pen and eraser act on ink; undo/redo reverse and reapply changes while editing the current canvas. Navigation gestures do not unintentionally add strokes. Undo history is an editing-session convenience; it is not promised across reopening a page or app restart.

## 3. Save, switch notes, reopen, and edit original strokes

- Tap **Save**, wait for **Saved on this iPad**, create a second note, write something different, and return to `Physics test`.
- Erase only part of an original stroke in the first note and save it.
- Add a page, draw a large `2`, then navigate back and forth using the page arrows. Switch between both notes.

**Expected:** Each note/page has its own drawing. The original stroke can still be edited with PencilKit. No flattened PNG/PDF replaces the source drawing. No drawing from another page appears. Unsaved-storage errors must be visible and must not silently permit a note switch that loses pending changes.

## 4. Background, close, and relaunch persistence

- Complete a new stroke, leave the app for the Home Screen, and return. Repeat after explicitly tapping Save and waiting for its saved status.
- Close the running app through the app switcher, reopen the same Swift Playground App project, and run it again. Keep the same bundle identifier and project.
- Check titles, page order, stroke edits, and chosen destination if one was previously set. Reopen the saved empty note too.

**Expected:** Saved notes survive and remain editable. Backgrounding triggers a save attempt. A stroke interrupted before PencilKit finishes reporting it is not a durability guarantee; finish strokes and confirm Save before relying on a force-close test. Do not delete the app or project as a substitute for a normal restart.

## 5. PNG export, share sheet, and editable backup

- Open a two-page test note. Choose **Export → PNG · all pages**, then **Save to Files**. Open both numbered images in Files; optionally use a share-sheet Photos action if offered.
- Verify white backgrounds, legible equations, all four edge labels, correct page numbers, and no clipped off-screen content.
- Choose **Export → Editable Backup** and save the `.pencilnote` file to Files or iCloud Drive. Use the sidebar's **Restore Backup** button to import it.
- Open the imported copy and erase a saved stroke. Switch between the original and imported notes, editing them differently.

**Expected:** The iPad share sheet opens without a popover crash. PNG export creates one image per page, including blank pages. Restoring creates a separate editable note and preserves the original. The restored note has no destination/sync linkage, and edits to one copy do not alter the other. The backup contains note/stroke data, never a Notion credential.

## 6. Ordered PDF and out-of-paper ink

- On a test note, label three pages `1`, `2`, and `3`, including an equation near each page's bottom-right corner. Export **PDF · all pages** and open it in Files.
- On a disposable page, use PencilKit's lasso to select a recognizable stroke and move it partly beyond the paper edge if the device tool permits this. Export both PNG and PDF.
- If the lasso cannot move ink beyond the paper, record that subcase as **not run**, not passed. Do not infer it from an ordinary on-paper export.

**Expected:** PDF contains exactly three pages in the correct order and includes the lower/off-screen content. Export fits the complete stored drawing bounds, including out-of-paper lasso strokes, into the output while preserving aspect ratio. This may make the whole drawing smaller; it must not crop those strokes. Original editable strokes remain intact. PDF handwriting is rendered image content, not searchable text or guaranteed vector ink.

## 7. Secure connection and Keychain restart

- Create the personal internal integration and page connection described in [Notion setup](NOTION_SETUP.md).
- Open the app's gear button, paste the secret into **Internal integration token**, and tap **Connect Notion**. Do not capture the secret in screenshots or logs.
- Confirm the field clears after success. Close/reopen the app under the same identity, open settings, and tap **Verify Connection**.
- Tap **Disconnect**, restart again, and confirm it is disconnected. Reconnect to continue testing.

**Expected:** A valid token verifies and is retained through the app's Keychain without repasting after a normal restart. The restored connection is labeled as saved until online verification. Disconnect removes the stored token. No token appears in notes, exported backups, success/error text, or source files. A revoked/invalid token produces an actionable error without damaging local notes. Keychain persistence across deleting the app or changing signing identity is not promised.

## 8. Authorized destinations and missing permissions

- Search for and select the connected disposable page. If practical, create two pages with the same title and use the displayed page-ID prefix to distinguish them.
- Confirm a page that is not connected to the integration is absent. Connect it, allow indexing time, and use Refresh/search again.
- For a disposable connected page, temporarily remove the connection or an integration capability, attempt discovery/sync, then restore it and retry.
- If your workspace has more than 100 accessible pages, verify that results beyond the first API page can be found. Otherwise record the live-pagination subcase as not run; automated contract tests are separate evidence.

**Expected:** Only accessible results are offered; empty/untitled results have understandable UI; the selected destination persists per note. Missing access gives a useful error and no blind append. Newly shared pages need not appear immediately. A user-visible Notion page is not automatically API-accessible.

## 9. Sync, repeat, update, formats, and file limits

- Select PDF, tap **Sync to Notion**, and open the actual attachment in the selected Notion page. Inspect every page and equation.
- Tap sync again without edits, then add a stroke and sync once more using the same format and destination. Count the app's attachment blocks.
- On a single-page test note, switch to PNG and sync. Switch back to PDF and sync. Change destination to a second authorized page and sync; then return to the first.
- On a multipage note, attempt PNG sync. For an optional size-limit check, use a disposable large note whose actual export exceeds your reported upload limit; do not assume a particular number of pages will reach it.

**Expected:** Progress culminates in a real visible attachment. No-change sync adds no block; changed content replaces the same note/format block. Format/destination changes preserve older blocks and reconcile matching blocks when returning. PNG sync rejects multipage notebooks with guidance to choose PDF, while local PNG export still exports all pages. Over-limit files are rejected with their size/limit and original strokes remain safe. The cap is the smaller of the returned workspace allowance and 20 MiB; missing allowance uses 5 MiB. If no oversized export was tested, mark that subcase not run.

## 10. Offline retry, uncertain writes, and deleted-block recovery

- With a valid connection saved, enable Airplane Mode and ensure Wi-Fi is also off. Edit/save locally and attempt sync.
- Restore connectivity and retry. Inspect the destination and count matching blocks.
- Optional uncertain-write test: on a disposable page, interrupt connectivity late in an upload/append. It may be hard to hit the ambiguous moment. If the app reports an uncertain previous sync, keep its **original format and destination**, wait, then retry reconciliation.
- Inspect Notion before using **••• → Resolve uncertain sync → I checked: no block exists**. Use that reset only if the original page truly contains no corresponding block. Record the ambiguous-write subcase as not run if it was not actually induced.
- In Notion, delete the linked block of a disposable note. Make a new local edit and sync to exercise the stale block ID. After confirming the deletion and destination, use **••• → Reset Notion link**, then sync again. Repeat with a moved block only if desired, noting the block on the other page remains there.

**Expected:** Offline failures preserve saved local ink. A normal retry updates/reconciles rather than duplicating page blocks. An ambiguous append blocks blind re-appending and requires recovery. Deleted-block failures do not silently create a duplicate; explicit Reset Notion link rechecks the chosen page. Missing page permissions must be fixed, not bypassed with a reset. Delayed Notion visibility, modified captions, and concurrent clients still prevent an absolute exactly-once guarantee.

## Additional destructive/error checks

Use disposable copies only. Cancel **Delete Current Page** and **Delete Note** first and confirm nothing changes; then confirm each deletion and check the expected page/note disappears while the separate backup and Notion copy remain. The final page cannot be removed on its own.

Import an empty/invalid `.pencilnote` copy and confirm a readable error without replacing existing notes. Do not corrupt the app's only copy to test recovery. Local persistence retains a previous file version and reports unreadable files; exact on-device corruption and interrupted-write behavior still require controlled device testing.

If a genuine low-storage error occurs, verify the app reports **Not saved** and retains the in-memory note for retry. Free storage, tap Save, and check persistence after reopening. Do not deliberately fill your personal iPad to simulate this condition. Record this subcase as not run if it was not safely exercised.
