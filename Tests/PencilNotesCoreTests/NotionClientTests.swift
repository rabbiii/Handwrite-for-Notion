import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PencilNotesCore

private final class NotionStubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class NotionClientTests: XCTestCase {
    private var session: URLSession!
    private var client: NotionClient!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NotionStubProtocol.self]
        session = URLSession(configuration: configuration)
        client = NotionClient(token: "unit-test-token", session: session, minimumRequestInterval: 0)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        NotionStubProtocol.handler = nil
        client = nil
        session = nil
        super.tearDown()
    }

    private static func reply(_ request: URLRequest, _ json: [String: Any], status: Int = 200,
                              headers: [String: String] = [:]) throws -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!,
         try JSONSerialization.data(withJSONObject: json))
    }

    private static func body(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            body.append(contentsOf: buffer.prefix(count))
        }
        return body
    }

    private static func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: body(request)) as? [String: Any])
    }

    func testConnectionUsesPinnedVersionAndActualWorkspaceLimit() async throws {
        NotionStubProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.notion.com/v1/users/me")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2026-03-11")
            return try Self.reply(request, ["name": "Integration", "bot": ["workspace_name": "School", "workspace_limits": ["max_file_upload_size_in_bytes": 5_242_880]]])
        }
        let connection = try await client.connection()
        XCTAssertEqual(connection, NotionConnection(name: "School", maxUploadBytes: 5_242_880))
    }

    func testConnectionMissingLimitFallsBackConservatively() async throws {
        NotionStubProtocol.handler = { try Self.reply($0, ["bot": [:], "name": "Personal notes"]) }
        let connection = try await client.connection()
        XCTAssertEqual(connection.name, "Personal notes")
        XCTAssertEqual(connection.maxUploadBytes, NotionClient.conservativeUploadLimit)
    }

    func testPageSearchPaginatesAndPreservesDistinctPagesWithSameTitle() async throws {
        var count = 0
        NotionStubProtocol.handler = { request in
            count += 1
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/search")
            let body = try Self.jsonBody(request)
            XCTAssertEqual(body["query"] as? String, "Physics")
            XCTAssertEqual(body["page_size"] as? Int, 100)
            XCTAssertEqual((body["filter"] as? [String: String])?["value"], "page")
            if count == 1 {
                XCTAssertNil(body["start_cursor"])
                return try Self.reply(request, ["has_more": true, "next_cursor": "cursor-two", "results": [
                    ["object": "page", "id": "first", "properties": ["Name": ["type": "title", "title": [["plain_text": "Physics"]]]]],
                    ["object": "page", "id": "trashed", "in_trash": true, "properties": [:]]
                ]])
            }
            XCTAssertEqual(body["start_cursor"] as? String, "cursor-two")
            return try Self.reply(request, ["has_more": false, "next_cursor": NSNull(), "results": [
                ["object": "page", "id": "first", "properties": [:]],
                ["object": "page", "id": "second", "properties": ["title": ["title": [["text": ["content": "Physics"]]]]]],
                ["object": "page", "id": "third", "properties": [:]]
            ]])
        }
        let pages = try await client.searchPages(query: " Physics ")
        XCTAssertEqual(count, 2)
        XCTAssertEqual(pages.map(\.id), ["first", "second", "third"])
        XCTAssertEqual(pages.map(\.title), ["Physics", "Physics", "Untitled page"])
    }

    func testRepeatedCursorIsRejectedInsteadOfLoopingForever() async throws {
        var count = 0
        NotionStubProtocol.handler = { request in
            count += 1
            return try Self.reply(request, ["results": [], "has_more": true, "next_cursor": "same"])
        }
        do {
            _ = try await client.searchPages(query: "")
            XCTFail("Repeated cursor must fail")
        } catch let error as NotionError {
            XCTAssertFalse(error.isAmbiguousMutation)
            XCTAssertEqual(count, 2)
        }
    }

    func testUploadSendsCorrectMultipartAndOnlyAcceptsConfirmedUpload() async throws {
        let bytes = Data([0x89, 0x50, 0x4e, 0x47, 0x00, 0xff])
        var calls = 0
        var progress: [String] = []
        NotionStubProtocol.handler = { request in
            calls += 1
            XCTAssertEqual(request.httpMethod, "POST")
            if calls == 1 {
                XCTAssertEqual(request.url?.path, "/v1/file_uploads")
                let json = try Self.jsonBody(request)
                XCTAssertEqual(json["mode"] as? String, "single_part")
                XCTAssertEqual(json["filename"] as? String, "page.png")
                XCTAssertEqual(json["content_type"] as? String, "image/png")
                return try Self.reply(request, ["id": "upload-1", "status": "pending"])
            }
            XCTAssertEqual(request.url?.path, "/v1/file_uploads/upload-1/send")
            let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
            XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
            let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
            let body = try Self.body(request)
            XCTAssertTrue(body.starts(with: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"page.png\"\r\nContent-Type: image/png\r\n\r\n".utf8)))
            XCTAssertNotNil(body.range(of: bytes))
            XCTAssertTrue(body.suffix(Data("\r\n--\(boundary)--\r\n".utf8).count) == Data("\r\n--\(boundary)--\r\n".utf8))
            return try Self.reply(request, ["id": "upload-1", "status": "uploaded"])
        }
        let id = try await client.upload(data: bytes, filename: "page.png", contentType: "image/png", maxBytes: 1000) { progress.append($0) }
        XCTAssertEqual(id, "upload-1")
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(progress, ["Preparing upload…", "Uploading file…", "File uploaded"])
    }

    func testOversizedUploadFailsBeforeNetwork() async throws {
        var called = false
        NotionStubProtocol.handler = { request in called = true; return try Self.reply(request, [:]) }
        do {
            _ = try await client.upload(data: Data(repeating: 0, count: 11), filename: "page.pdf", contentType: "application/pdf", maxBytes: 10) { _ in }
            XCTFail("Oversized upload must fail")
        } catch let error as NotionError { XCTAssertTrue(error.localizedDescription.contains("upload limit")) }
        XCTAssertFalse(called)
    }

    func testUnconfirmedUploadDoesNotReportSuccess() async throws {
        var calls = 0
        NotionStubProtocol.handler = { request in calls += 1; return try Self.reply(request, ["id": "upload-1", "status": "pending"]) }
        do {
            _ = try await client.upload(data: Data([1]), filename: "page.pdf", contentType: "application/pdf", maxBytes: 100) { _ in }
            XCTFail("Pending upload must not succeed")
        } catch let error as NotionError { XCTAssertTrue(error.localizedDescription.contains("not confirmed")) }
        XCTAssertEqual(calls, 2)
    }

    func testFindBlockPaginatesAndReadsCaptionMarker() async throws {
        var calls = 0
        NotionStubProtocol.handler = { request in
            calls += 1
            XCTAssertEqual(request.url?.path, "/v1/blocks/page-1/children")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(query?.first { $0.name == "page_size" }?.value, "100")
            if calls == 1 {
                return try Self.reply(request, ["results": [["id": "other", "type": "paragraph", "paragraph": [:]]], "has_more": true, "next_cursor": "a+b/c="])
            }
            XCTAssertEqual(query?.first { $0.name == "start_cursor" }?.value, "a+b/c=")
            return try Self.reply(request, ["has_more": false, "results": [
                ["id": "found", "type": "pdf", "pdf": ["caption": [["plain_text": "Lecture · "], ["text": ["content": "PencilNotes:note-id"]]]]]
            ]])
        }
        let id = try await client.findBlock(pageID: "page-1", marker: "PencilNotes:note-id")
        XCTAssertEqual(id, "found")
        XCTAssertEqual(calls, 2)
    }

    func testAppendThenUpdateUsesOfficialBlockBodies() async throws {
        var calls = 0
        NotionStubProtocol.handler = { request in
            calls += 1
            XCTAssertEqual(request.httpMethod, "PATCH")
            let body = try Self.jsonBody(request)
            if calls == 1 {
                XCTAssertEqual(request.url?.path, "/v1/blocks/page-1/children")
                let children = try XCTUnwrap(body["children"] as? [[String: Any]])
                XCTAssertEqual(children.count, 1)
                XCTAssertEqual(children[0]["type"] as? String, "pdf")
                let pdf = try XCTUnwrap(children[0]["pdf"] as? [String: Any])
                XCTAssertEqual(pdf["type"] as? String, "file_upload")
                XCTAssertEqual((pdf["file_upload"] as? [String: String])?["id"], "upload-1")
                return try Self.reply(request, ["results": [["id": "block-1"]]])
            }
            XCTAssertEqual(request.url?.path, "/v1/blocks/block-1")
            XCTAssertNil(body["children"])
            let pdf = try XCTUnwrap(body["pdf"] as? [String: Any])
            XCTAssertNil(pdf["type"])
            XCTAssertEqual((pdf["file_upload"] as? [String: String])?["id"], "upload-2")
            return try Self.reply(request, ["id": "block-1"])
        }
        let id = try await client.appendFile(pageID: "page-1", uploadID: "upload-1", format: .pdf, caption: "Title · PencilNotes:note-id")
        XCTAssertEqual(id, "block-1")
        try await client.updateFile(blockID: id, uploadID: "upload-2", format: .pdf, caption: "Updated · PencilNotes:note-id")
        XCTAssertEqual(calls, 2)
    }

    func testMutationServerFailureIsAmbiguousAndNeverAutomaticallyRetried() async throws {
        var calls = 0
        NotionStubProtocol.handler = { request in calls += 1; return try Self.reply(request, ["code": "internal_server_error", "message": "Try again"], status: 503) }
        do {
            _ = try await client.appendFile(pageID: "page-1", uploadID: "upload-1", format: .png, caption: "marker")
            XCTFail("Server failure must propagate")
        } catch let error as NotionError { XCTAssertTrue(error.isAmbiguousMutation) }
        XCTAssertEqual(calls, 1)
    }

    func testOfflineMutationIsAmbiguous() async throws {
        NotionStubProtocol.handler = { _ in throw URLError(.networkConnectionLost) }
        do {
            _ = try await client.appendFile(pageID: "page-1", uploadID: "upload-1", format: .pdf, caption: "marker")
            XCTFail("Transport failure must propagate")
        } catch let error as NotionError {
            XCTAssertTrue(error.isAmbiguousMutation)
            XCTAssertTrue(error.localizedDescription.contains("internet"))
        }
    }

    func testRateLimitIncludesRetryAfterWithoutExposingToken() async throws {
        var calls = 0
        NotionStubProtocol.handler = { request in
            calls += 1
            return try Self.reply(request, ["code": "rate_limited", "message": "unit-test-token"], status: 429, headers: ["Retry-After": "3"])
        }
        do {
            _ = try await client.searchPages(query: "")
            XCTFail("Rate limit must propagate")
        } catch let error as NotionError {
            XCTAssertEqual(error.retryAfter, 3)
            XCTAssertTrue(error.localizedDescription.contains("3 seconds"))
            XCTAssertFalse(error.localizedDescription.contains("unit-test-token"))
        }
        XCTAssertEqual(calls, 1)
    }

    func testPermissionFailureHasActionableMessage() async throws {
        NotionStubProtocol.handler = { try Self.reply($0, ["code": "restricted_resource"], status: 403) }
        do {
            _ = try await client.searchPages(query: "")
            XCTFail("Permission failure must propagate")
        } catch let error as NotionError {
            XCTAssertFalse(error.isAmbiguousMutation)
            XCTAssertTrue(error.localizedDescription.contains("read, insert, and update"))
        }
    }
}
