import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The account's real upload limit is preferred over plan-name assumptions.
struct NotionConnection: Equatable {
    let name: String
    let maxUploadBytes: Int
}

enum NotionError: LocalizedError {
    case invalidInput(String)
    case response(status: Int, code: String, message: String, retryAfter: TimeInterval?, mutation: Bool)
    case transport(message: String, mutation: Bool)
    case invalidResponse(mutation: Bool)

    /// The caller must reconcile its saved marker before repeating an uncertain append.
    var isAmbiguousMutation: Bool {
        switch self {
        case .transport(_, let mutation), .invalidResponse(let mutation): return mutation
        case .response(let status, _, _, _, let mutation): return mutation && status >= 500
        case .invalidInput: return false
        }
    }

    var retryAfter: TimeInterval? {
        if case .response(_, _, _, let seconds, _) = self { return seconds }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .invalidInput(let explanation): return explanation
        case .transport(let message, let mutation):
            return message + (mutation ? " The request may have reached Notion. Check the destination before trying again." : "")
        case .invalidResponse(let mutation):
            return "Notion returned an unexpected response." + (mutation ? " The write may have succeeded; check the destination before trying again." : " Try again later.")
        case .response(let status, _, let message, let retryAfter, _):
            switch status {
            case 401: return "Notion rejected this token. Reconnect in Notion Settings with a valid integration token."
            case 403: return "The integration does not have permission for this action. Enable read, insert, and update content, and connect it to the destination page."
            case 404: return "Notion could not find this page or file. Check that the page still exists and is shared with this integration."
            case 409: return "Notion could not complete this change because the page changed. Check the destination, then retry."
            case 413: return "The file is too large for Notion. Export fewer pages or use a smaller PNG."
            case 429, 529:
                let wait = retryAfter.map { " Wait at least \(Int(ceil($0))) seconds before retrying." } ?? " Wait a moment before retrying."
                return "Notion is limiting requests." + wait
            case 500...599: return "Notion is temporarily unavailable. The change may have succeeded; check the destination before retrying."
            default: return message.isEmpty ? "Notion could not complete the request (HTTP \(status))." : "Notion: \(message)"
            }
        }
    }
}

/// Reserves request slots before suspension, so concurrent searches/uploads share one rate budget.
private actor NotionRequestGate {
    private var nextSlot = Date.distantPast
    let interval: TimeInterval

    init(interval: TimeInterval) { self.interval = max(0, interval) }

    func wait() async throws {
        try Task.checkCancellation()
        let now = Date()
        let slot = max(now, nextSlot)
        nextSlot = slot.addingTimeInterval(interval)
        let delay = slot.timeIntervalSince(now)
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        try Task.checkCancellation()
    }
}

/// Native, personal-use client. Tokens belong in Keychain and never in note files.
/// API contract checked against the official SDK; see docs/NOTION_API_RESEARCH.md.
final class NotionClient {
    static let apiVersion = "2026-03-11"
    static let conservativeUploadLimit = 5 * 1024 * 1024
    static let singlePartLimit = 20 * 1024 * 1024

    private let token: String
    private let session: URLSession
    private let gate: NotionRequestGate
    private let baseURL = URL(string: "https://api.notion.com/v1/")!

    init(token: String, session: URLSession = .shared, minimumRequestInterval: TimeInterval = 0.35) {
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
        self.gate = NotionRequestGate(interval: minimumRequestInterval)
    }

    func connection() async throws -> NotionConnection {
        let json = try await request(path: "users/me", method: "GET")
        guard let bot = json["bot"] as? [String: Any] else {
            throw NotionError.invalidInput("Use an internal integration token for this personal app. The supplied account is not an integration bot.")
        }
        let workspace = (bot["workspace_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let userName = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = [workspace, userName].compactMap { $0 }.first { !$0.isEmpty } ?? "Notion integration"
        let limits = bot["workspace_limits"] as? [String: Any]
        let maximum = (limits?["max_file_upload_size_in_bytes"] as? NSNumber)?.intValue
        return NotionConnection(name: name, maxUploadBytes: maximum.flatMap { $0 > 0 ? $0 : nil } ?? Self.conservativeUploadLimit)
    }

    /// Search indexes only accessible pages, not necessarily every page in a workspace.
    func searchPages(query: String) async throws -> [NotionPage] {
        var result: [NotionPage] = []
        var ids = Set<String>()
        var cursors = Set<String>()
        var cursor: String?
        repeat {
            var body: [String: Any] = ["filter": ["property": "object", "value": "page"], "page_size": 100]
            let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { body["query"] = cleaned }
            if let cursor { body["start_cursor"] = cursor }
            let json = try await request(path: "search", method: "POST", json: body, mutation: false)
            guard let items = json["results"] as? [[String: Any]] else { throw NotionError.invalidResponse(mutation: false) }
            for page in items {
                guard page["object"] as? String == "page", page["in_trash"] as? Bool != true,
                      page["archived"] as? Bool != true, let id = page["id"] as? String, !id.isEmpty else { continue }
                if ids.insert(id).inserted { result.append(NotionPage(id: id, title: Self.pageTitle(page))) }
            }
            cursor = try Self.nextCursor(json, seen: &cursors)
        } while cursor != nil
        return result
    }

    /// Single-part upload: no external hosting service and no multipart-complete operation.
    func upload(data: Data, filename: String, contentType: String, maxBytes: Int,
                progress: @escaping (String) -> Void) async throws -> String {
        let limit = min(maxBytes > 0 ? maxBytes : Self.conservativeUploadLimit, Self.singlePartLimit)
        guard !data.isEmpty else { throw NotionError.invalidInput("The export is empty. Draw something and export again.") }
        guard data.count <= limit else {
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)
            throw NotionError.invalidInput("This export is larger than the \(formatted) upload limit. Sync a smaller PNG or fewer pages. Your editable note stays on this iPad.")
        }
        guard ["image/png", "application/pdf"].contains(contentType) else {
            throw NotionError.invalidInput("Only PNG and PDF exports are supported.")
        }
        let safeName = Self.safeFilename(filename)
        progress("Preparing upload…")
        let created = try await request(path: "file_uploads", method: "POST", json: [
            "mode": "single_part", "filename": safeName, "content_type": contentType
        ], mutation: true)
        guard let uploadID = created["id"] as? String, !uploadID.isEmpty else { throw NotionError.invalidResponse(mutation: true) }
        try Self.validateID(uploadID)
        let boundary = "PencilNotes-\(UUID().uuidString)"
        var multipart = Data()
        multipart.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
        multipart.append(data)
        multipart.append(Data("\r\n--\(boundary)--\r\n".utf8))
        progress("Uploading file…")
        let sent = try await request(path: "file_uploads/\(uploadID)/send", method: "POST", body: multipart,
                                     contentType: "multipart/form-data; boundary=\(boundary)", mutation: true)
        guard sent["id"] as? String == uploadID, sent["status"] as? String == "uploaded" else {
            let status = sent["status"] as? String ?? "unknown"
            if status == "expired" || status == "failed" {
                throw NotionError.invalidInput("Notion marked the upload as \(status). No page block was added. Try syncing again.")
            }
            throw NotionError.invalidInput("Notion has not confirmed the file upload yet. No page block was added. Wait, then try syncing again.")
        }
        progress("File uploaded")
        return uploadID
    }

    /// Match title-link metadata and legacy visible markers after an interrupted append.
    func findBlock(pageID: String, marker: String) async throws -> String? {
        try Self.validateID(pageID)
        guard !marker.isEmpty else { throw NotionError.invalidInput("The saved sync marker is missing.") }
        var cursor: String?
        var cursors = Set<String>()
        repeat {
            var query = [URLQueryItem(name: "page_size", value: "100")]
            if let cursor { query.append(URLQueryItem(name: "start_cursor", value: cursor)) }
            let json = try await request(path: "blocks/\(pageID)/children", method: "GET", query: query)
            guard let items = json["results"] as? [[String: Any]] else { throw NotionError.invalidResponse(mutation: false) }
            for block in items {
                guard block["in_trash"] as? Bool != true, block["archived"] as? Bool != true,
                      let type = block["type"] as? String, ["image", "pdf"].contains(type),
                      let content = block[type] as? [String: Any], let caption = content["caption"] as? [[String: Any]],
                      Self.captionContainsMarker(caption, marker: marker), let id = block["id"] as? String, !id.isEmpty else { continue }
                return id
            }
            cursor = try Self.nextCursor(json, seen: &cursors)
        } while cursor != nil
        return nil
    }

    func appendFile(pageID: String, uploadID: String, format: ExportFormat, caption: String, captionLink: URL? = nil) async throws -> String {
        try Self.validateID(pageID)
        try Self.validateID(uploadID)
        let type = format == .png ? "image" : "pdf"
        let media = try Self.media(uploadID: uploadID, caption: caption, captionLink: captionLink, includeType: true)
        let json = try await request(path: "blocks/\(pageID)/children", method: "PATCH", json: [
            "children": [["object": "block", "type": type, type: media]]
        ], mutation: true)
        guard let blocks = json["results"] as? [[String: Any]], blocks.count == 1,
              let id = blocks.first?["id"] as? String, !id.isEmpty else { throw NotionError.invalidResponse(mutation: true) }
        return id
    }

    func updateFile(blockID: String, uploadID: String, format: ExportFormat, caption: String, captionLink: URL? = nil) async throws {
        try Self.validateID(blockID)
        try Self.validateID(uploadID)
        let type = format == .png ? "image" : "pdf"
        let json = try await request(path: "blocks/\(blockID)", method: "PATCH", json: [
            type: try Self.media(uploadID: uploadID, caption: caption, captionLink: captionLink, includeType: false)
        ], mutation: true)
        guard json["id"] as? String == blockID else { throw NotionError.invalidResponse(mutation: true) }
    }

    private func request(path: String, method: String, query: [URLQueryItem] = [], json: [String: Any]? = nil,
                         body: Data? = nil, contentType: String = "application/json", mutation: Bool = false) async throws -> [String: Any] {
        guard !token.isEmpty else { throw NotionError.invalidInput("Connect your integration in Notion Settings first.") }
        try Task.checkCancellation()
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw NotionError.invalidInput("The Notion request URL is invalid.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        try await gate.wait()
        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            let message: String
            switch (error as? URLError)?.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                message = "Could not reach Notion. Check your internet connection."
            case .timedOut: message = "The Notion request timed out."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
                message = "A secure connection to Notion could not be established. Check the iPad date and network."
            default: message = "The connection to Notion failed. Try another network or try again later."
            }
            throw NotionError.transport(message: message, mutation: mutation)
        }
        guard let http = response as? HTTPURLResponse else { throw NotionError.invalidResponse(mutation: mutation) }
        let decoded = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any]
        guard (200...299).contains(http.statusCode) else {
            let message = (decoded?["message"] as? String ?? "").replacingOccurrences(of: token, with: "[redacted]")
            throw NotionError.response(status: http.statusCode, code: decoded?["code"] as? String ?? "unknown",
                                       message: message, retryAfter: Self.retryDelay(http.value(forHTTPHeaderField: "Retry-After")), mutation: mutation)
        }
        guard let decoded else { throw NotionError.invalidResponse(mutation: mutation) }
        return decoded
    }

    private static func captionContainsMarker(_ caption: [[String: Any]], marker: String) -> Bool {
        if richText(caption).contains(marker) { return true }
        return caption.contains { item in
            let text = item["text"] as? [String: Any]
            let link = text?["link"] as? [String: Any]
            guard let url = link?["url"] as? String ?? item["href"] as? String,
                  let components = URLComponents(string: url),
                  components.scheme == "https", components.host == "www.notion.so" else { return false }
            return components.queryItems?.contains { $0.name == "pencilnotes" && $0.value == marker } == true
        }
    }

    private static func media(uploadID: String, caption: String, captionLink: URL?, includeType: Bool) throws -> [String: Any] {
        guard caption.utf16.count <= 2000 else { throw NotionError.invalidInput("The note title is too long to use as a Notion caption. Rename the note and retry.") }
        var text: [String: Any] = ["content": caption]
        if let captionLink { text["link"] = ["url": captionLink.absoluteString] }
        var value: [String: Any] = ["file_upload": ["id": uploadID], "caption": [["type": "text", "text": text]]]
        if includeType { value["type"] = "file_upload" }
        return value
    }

    private static func validateID(_ id: String) throws {
        let valid = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !id.isEmpty, id.count <= 100, id.unicodeScalars.allSatisfy({ valid.contains($0) }) else {
            throw NotionError.invalidInput("The saved Notion destination is invalid. Choose the page again.")
        }
    }

    private static func nextCursor(_ json: [String: Any], seen: inout Set<String>) throws -> String? {
        guard let more = json["has_more"] as? Bool else { throw NotionError.invalidResponse(mutation: false) }
        guard more else { return nil }
        guard let next = json["next_cursor"] as? String, !next.isEmpty, seen.count < 1000,
              seen.insert(next).inserted else { throw NotionError.invalidResponse(mutation: false) }
        return next
    }

    private static func pageTitle(_ page: [String: Any]) -> String {
        guard let properties = page["properties"] as? [String: [String: Any]] else { return "Untitled page" }
        for key in properties.keys.sorted() {
            if let title = properties[key]?["title"] as? [[String: Any]] {
                let text = richText(title).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        return "Untitled page"
    }

    private static func richText(_ items: [[String: Any]]) -> String {
        items.map { ($0["plain_text"] as? String) ?? (($0["text"] as? [String: Any])?["content"] as? String) ?? "" }.joined()
    }

    private static func safeFilename(_ input: String) -> String {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "\"\\/"))
        let name = String(input.unicodeScalars.map { forbidden.contains($0) ? "_" : String($0) }.joined().prefix(150))
        return name.isEmpty ? "PencilNotes-export" : name
    }

    private static func retryDelay(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = TimeInterval(value), seconds.isFinite { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSinceNow) }
    }
}
