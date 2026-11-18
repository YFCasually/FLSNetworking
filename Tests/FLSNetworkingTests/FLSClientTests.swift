import Foundation
import Testing
@testable import FLSNetworking

private struct FLSStubResponse: Sendable {
    let status: Int
    var data = Data()
}

// Foundation invokes URLProtocol on its own queues. All shared handlers are lock protected.
private final class FLSURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: @Sendable (URLRequest) throws -> FLSStubResponse?] = [:]

    static func register(host: String, handler: @escaping @Sendable (URLRequest) throws -> FLSStubResponse?) {
        lock.withLock { handlers[host] = handler }
    }

    static func unregister(host: String) { _ = lock.withLock { handlers.removeValue(forKey: host) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let handler = Self.lock.withLock { Self.handlers[request.url?.host ?? ""] }
        do {
            guard let handler else { throw URLError(.resourceUnavailable) }
            guard let stub = try handler(request) else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

@Suite(.timeLimit(.minutes(1)))
struct FLSClientTests {
    private func client(host: String, logger: (@Sendable (FLSNetworkLogEvent) -> Void)? = nil) throws -> FLSNetworkClient {
        let config = try FLSNetworkConfiguration(baseURL: #require(URL(string: "https://\(host)/api")), logger: logger)
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [FLSURLProtocol.self]
        return FLSNetworkClient(configuration: config, sessionConfiguration: session)
    }

    @Test func acceptsEmpty204() async throws {
        let host = "\(UUID().uuidString).example.com"
        FLSURLProtocol.register(host: host) { _ in FLSStubResponse(status: 204) }
        defer { FLSURLProtocol.unregister(host: host) }
        let response = try await client(host: host).execute(FLSRequest(path: "x"))
        #expect(response.statusCode == 204)
        #expect(response.data.isEmpty)
    }

    @Test func preservesHTTPErrorBody() async throws {
        let host = "\(UUID().uuidString).example.com"
        FLSURLProtocol.register(host: host) { _ in FLSStubResponse(status: 503, data: Data("unavailable".utf8)) }
        defer { FLSURLProtocol.unregister(host: host) }
        do {
            _ = try await client(host: host).execute(FLSRequest(path: "x"))
            Issue.record("Expected HTTP error")
        } catch FLSNetworkError.httpStatus(let response) {
            #expect(response.statusCode == 503)
            #expect(String(data: response.data, encoding: .utf8) == "unavailable")
        }
    }

    @Test func preservesTransportFailure() async throws {
        let host = "\(UUID().uuidString).example.com"
        FLSURLProtocol.register(host: host) { _ in throw URLError(.notConnectedToInternet) }
        defer { FLSURLProtocol.unregister(host: host) }
        do {
            _ = try await client(host: host).execute(FLSRequest(path: "x"))
            Issue.record("Expected transport error")
        } catch FLSNetworkError.transport { }
    }

    @Test func cancellationStopsInflightRequest() async throws {
        let host = "\(UUID().uuidString).example.com"
        let signal = AsyncStream.makeStream(of: Bool.self)
        FLSURLProtocol.register(host: host) { _ in
            signal.continuation.yield(true)
            signal.continuation.finish()
            return nil
        }
        defer { FLSURLProtocol.unregister(host: host) }
        let client = try client(host: host)
        let task = Task { try await client.execute(FLSRequest(path: "x")) }
        for await _ in signal.stream { break }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func alreadyCancelledTaskNeverSends() async throws {
        let host = "\(UUID().uuidString).example.com"
        FLSURLProtocol.register(host: host) { _ in
            Issue.record("Cancelled task must not reach transport")
            return FLSStubResponse(status: 200)
        }
        defer { FLSURLProtocol.unregister(host: host) }
        let client = try client(host: host)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.execute(FLSRequest(path: "x"))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func cancellationStopsInflightDownload() async throws {
        let host = "\(UUID().uuidString).example.com"
        let signal = AsyncStream.makeStream(of: Bool.self)
        FLSURLProtocol.register(host: host) { _ in
            signal.continuation.yield(true)
            signal.continuation.finish()
            return nil
        }
        defer { FLSURLProtocol.unregister(host: host) }
        let client = try client(host: host)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let task = Task { try await client.download(FLSRequest(path: "file"), to: destination) }
        for await _ in signal.stream { break }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func rejectsDirectoryUpload() async throws {
        let host = "\(UUID().uuidString).example.com"
        let client = try client(host: host)
        await #expect(throws: FLSNetworkError.self) {
            try await client.upload(fileURL: FileManager.default.temporaryDirectory, to: FLSRequest(path: "file", method: .post))
        }
    }

    @Test func signedUploadOmitsAPIAndSessionCredentials() async throws {
        let host = "\(UUID().uuidString).example.com"
        let signedURL = try #require(URL(string: "https://\(host)/object?signature=a%2Bb%3D"))
        FLSURLProtocol.register(host: host) { request in
            #expect(request.url == signedURL)
            #expect(request.httpMethod == "PUT")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "X-API") == nil)
            #expect(request.value(forHTTPHeaderField: "X-Session") == nil)
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
            return FLSStubResponse(status: 204)
        }
        defer { FLSURLProtocol.unregister(host: host) }
        let config = try FLSNetworkConfiguration(
            baseURL: #require(URL(string: "https://api.example.com")), defaultHeaders: ["X-API": "private"],
            headerProvider: { Issue.record("Signed uploads must bypass provider"); return ["Authorization": "private"] },
            requestAdapter: { request in Issue.record("Signed uploads must bypass adapter"); return request }
        )
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [FLSURLProtocol.self]
        session.httpAdditionalHeaders = ["X-Session": "private"]
        let client = FLSNetworkClient(configuration: config, sessionConfiguration: session)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("bytes".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let response = try await client.upload(fileURL: file, to: signedURL, headers: ["Content-Type": "application/octet-stream"])
        #expect(response.statusCode == 204)
    }

    @Test func emitsOnlySafeLogMetadata() async throws {
        let host = "\(UUID().uuidString).example.com"
        let events = AsyncStream.makeStream(of: FLSNetworkLogEvent.self)
        FLSURLProtocol.register(host: host) { _ in FLSStubResponse(status: 200) }
        defer { FLSURLProtocol.unregister(host: host) }
        let client = try client(host: host, logger: { events.continuation.yield($0); events.continuation.finish() })
        _ = try await client.execute(FLSRequest(path: "secret", queryItems: [.init(name: "token", value: "private")]))
        for await event in events.stream {
            #expect(event.host == host)
            #expect(event.outcome == .success)
            #expect(event.statusCode == 200)
            #expect(event.duration >= 0)
        }
    }
}
