# Notion API research and implementation contract

Reviewed 11 November 2026 (Asia/Dhaka). This application is a personal, single-owner native client. It does not use a paid server, OCR service, or a public OAuth client secret.

## Evidence and verification boundary

The cloud network denied `developers.notion.com` with HTTP CONNECT 403. The official Notion JavaScript SDK repository **was retrieved successfully** from GitHub, including its README, request implementation, and generated API models. The repository HEAD observed during research was `48a731c552cc1f72d548a91aaeadd5eea14c1245`. These are primary, implementation-level Notion sources, not a third-party tutorial. The links to the developer documentation below are intended for on-device reference; their page text was not retrieved in this environment. No real token was supplied and no live workspace mutation was tested.

Retrieved primary sources:

- [Official SDK README: supported versions, personal tokens, and retry policy](https://github.com/makenotion/notion-sdk-js/blob/48a731c552cc1f72d548a91aaeadd5eea14c1245/README.md)
- [File upload request/response models](https://github.com/makenotion/notion-sdk-js/blob/48a731c552cc1f72d548a91aaeadd5eea14c1245/src/api-endpoints/file-uploads.ts)
- [Search request model](https://github.com/makenotion/notion-sdk-js/blob/48a731c552cc1f72d548a91aaeadd5eea14c1245/src/api-endpoints/search.ts)
- [Block update, append, and list request models](https://github.com/makenotion/notion-sdk-js/blob/48a731c552cc1f72d548a91aaeadd5eea14c1245/src/api-endpoints/blocks.ts)
- [Bot workspace limits and media block models](https://github.com/makenotion/notion-sdk-js/blob/48a731c552cc1f72d548a91aaeadd5eea14c1245/src/api-endpoints/common.ts)
- [Request headers and conservative retry implementation](https://github.com/makenotion/notion-sdk-js/blob/48a731c552cc1f72d548a91aaeadd5eea14c1245/src/Client.ts)

## Authentication and version

Use a personal internal integration/connection created by the owner for their own workspace. The user enters the integration token in the app, never into source files or chat. Store it in the iPad Keychain; send it only over HTTPS to `api.notion.com`. This design avoids publishing a shared application secret. A distributed multi-user product would require a separate OAuth/security design.

The current official SDK README expressly supports **`2026-03-11`** and `2025-09-03`. Its default remains `2025-09-03`, so copying only the SDK default would miss its documented newer supported version. Pin the app to `2026-03-11`; do not claim that a pinned version can never change.

Every API request uses:

```http
Authorization: Bearer <owner-entered token>
Notion-Version: 2026-03-11
```

JSON requests additionally use `Content-Type: application/json`. File sending uses a valid multipart boundary instead.

`GET https://api.notion.com/v1/users/me` verifies the token. Read the returned bot's optional `bot.workspace_name` and `bot.workspace_limits.max_file_upload_size_in_bytes`. The generated bot model exposes the workspace-specific maximum, avoiding assumptions about a user's plan. If that value is unavailable, the application should conservatively cap exports at 5 MiB and explain the fallback. A 20 MiB cap is additionally necessary for the single-part upload implementation.

Set integration capabilities to **Read content**, **Insert content**, and **Update content**. Read content enables page discovery/reconciliation, insert enables new blocks, and update enables replacing the app's existing uploaded image/PDF. The implementation does not need user email, comment, or unrelated workspace permissions. In Notion, explicitly add the integration/connection to each destination page (page menu → Connections / Add connections; wording may vary). Search permissions are scoped to the integration, not the signed-in user's complete workspace.

Reference: [authorization](https://developers.notion.com/reference/authentication), [internal connections](https://developers.notion.com/guides/get-started/create-a-notion-integration), [retrieve token bot](https://developers.notion.com/reference/get-self).

## Page discovery

```http
POST /v1/search
```

```json
{
  "query": "optional title search",
  "filter": { "property": "object", "value": "page" },
  "page_size": 100,
  "sort": { "direction": "descending", "timestamp": "last_edited_time" }
}
```

For subsequent pages, add `"start_cursor": "<next_cursor>"`. Continue while `has_more` is true. A missing/repeated cursor despite `has_more` should produce a useful error, not an infinite loop. Read the title from whichever page property has `type: "title"`; concatenate all text items and fall back to “Untitled”. Ignore trashed/archived entries. The API performs title search, not full handwritten-content search. Results depend on sharing, integration permissions, and indexing; they are not a promise to enumerate every workspace page.

Reference: [search](https://developers.notion.com/reference/post-search), [search limitations](https://developers.notion.com/reference/search-optimizations-and-limitations).

## Official single-part file upload

1. Export a PNG (`image/png`) or PDF (`application/pdf`). Check actual byte count against the smaller of workspace maximum and 20 MiB before upload.
2. Create an upload:

```http
POST /v1/file_uploads
```

```json
{"mode":"single_part","filename":"Lecture.pdf","content_type":"application/pdf"}
```

3. Capture the upload object's `id`. Send the data:

```http
POST /v1/file_uploads/<id>/send
Content-Type: multipart/form-data; boundary=<random boundary>
```

Multipart body includes exactly the `file` field, filename, MIME type, CRLF framing, bytes, and closing boundary. For single-part uploads, omit `part_number`. Do not invoke the multipart completion endpoint for this workflow.

4. Require the returned upload `status` to be `uploaded` before attachment. `pending`, `expired`, and `failed` are actual modeled statuses. Retrieve the object using `GET /v1/file_uploads/<id>` if status confirmation is needed. Use `expiry_time` if available; avoid hardcoding lifetime assumptions. Upload and attach during the same foreground operation. An uploaded file is not yet visible in the page until a block references it.
5. Append an image/PDF block to the selected page:

```http
PATCH /v1/blocks/<destination-page-id>/children
```

```json
{
  "children": [{
    "object": "block",
    "type": "pdf",
    "pdf": {
      "type": "file_upload",
      "file_upload": { "id": "<upload-id>" },
      "caption": [{"type":"text","text":{"content":"Lecture · PencilNotes:<stable-note-UUID>"}}]
    }
  }]
}
```

For an image, replace both `pdf` values with `image`. Persist the returned block ID with note and destination IDs.

6. To replace a previous upload on a later sync:

```http
PATCH /v1/blocks/<existing-block-id>
```

```json
{
  "pdf": {
    "file_upload": { "id": "<new-upload-id>" },
    "caption": [{"type":"text","text":{"content":"Lecture · PencilNotes:<stable-note-UUID>"}}]
  }
}
```

The update payload intentionally does not require the media `type` field. The generated current model permits `file_upload` and caption on both image and PDF updates. Prefer a stable sync format so a note can replace the same block type.

Reference: [create upload](https://developers.notion.com/reference/create-a-file-upload), [send upload](https://developers.notion.com/reference/send-a-file-upload), [append blocks](https://developers.notion.com/reference/patch-block-children), [update block](https://developers.notion.com/reference/update-a-block), [upload guide](https://developers.notion.com/guides/data-apis/uploading-small-files).

## Retries, permissions, and duplication

- Serial requests spaced at least about 350 ms apart are a conservative choice; always honor a valid `Retry-After` on HTTP 429. The official SDK also handles HTTP 529 overload and retry-after dates.
- Do **not** automatically repeat a block append after a timeout, lost connection, or ambiguous HTTP 5xx. The official SDK deliberately retries 500/503 only for GET/DELETE, because repeating writes can duplicate side effects.
- Disable overlapping sync actions. Before creating a new block, list all destination children (100 per page, using `next_cursor`) and reconcile the exact stable note marker in media captions. If one matching block exists, update it. Persist block IDs immediately after confirmation. After an uncertain write, require reconciliation before allowing another append.
- This is practical duplicate reduction, **not an exactly-once guarantee**: there is no documented idempotency-key parameter in the retrieved append contract; concurrent devices, removed captions, and consistency delays can still defeat reconciliation. If an ambiguous append cannot be reconciled, stop and ask the owner to inspect the destination instead of silently creating another block.
- HTTP 401 means reconnect/re-enter a valid token. HTTP 403/404 can mean missing capabilities, a page not shared with the integration, a removed page/block, or revoked access. Do not treat a 404 on a saved block as permission to blindly append elsewhere. HTTP 400 may include file limits, unsupported MIME types, or invalid payload. Show actionable human-readable context without logging tokens or full network headers.
- A failed upload may leave an unattached upload object. Retrying can create another transient upload, but should not create another page block until reconciliation is safe.

Reference: [request limits](https://developers.notion.com/reference/request-limits), [status codes](https://developers.notion.com/reference/status-codes), and the retrieved official SDK retry implementation linked above. The usual published average rate and numeric free-plan limit were not independently verified from the blocked documentation website; using the returned workspace limit and server `Retry-After` avoids relying solely on those figures.

## Meaning of sync

The destination contains a rendered image/PDF. Original `PKDrawing` strokes remain local and editable in PencilNotes. This does not create editable Notion ink, real-time collaboration, or two-way synchronization. Token creation and a live upload must be acceptance-tested on the owner's iPad; local mock/contract tests cannot certify their actual Notion permissions.
