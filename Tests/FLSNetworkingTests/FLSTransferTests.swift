import Foundation
import Network
import Testing
@testable import FLSNetworking

/// A loopback-only HTTP fixture exercises URLSession's real download and redirect behavior.
private final class FLSLoopbackServer: Sendable {
    let listener: NWListener
    private let response: @Sendable (String) -> (Int, [String: String], Data)

    init(response: @escaping @Sendable (String) -> (Int, [String: String], Data)) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        self.response = response
    }

    func start() async throws -> URL {
        let ready = AsyncStream.makeStream(of: Bool.self)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.continuation.yield(true); ready.continuation.finish()
            case .failed, .cancelled: ready.continuation.finish()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: DispatchQueue(label: "FLSNetworkingTests.connection"))
            self?.receive(connection, buffer: Data())
        }
        listener.start(queue: DispatchQueue(label: "FLSNetworkingTests.server"))
        for await _ in ready.stream {
            let port = try #require(listener.port)
            return try #require(URL(string: "http://127.0.0.1:\(port.rawValue)"))
        }
        throw URLError(.cannotConnectToHost)
    }

    func stop() { listener.cancel() }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            buffer.append(data ?? Data())
            guard let text = String(data: buffer, encoding: .utf8), text.contains("\r\n\r\n") else {
                if complete || error != nil { connection.cancel() }
                else { self.receive(connection, buffer: buffer) }
                return
            }
            let (status, headers, body) = self.response(text)
            var output = "HTTP/1.1 \(status) Test\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
            for (key, value) in headers { output += "\(key): \(value)\r\n" }
            output += "\r\n"
            var bytes = Data(output.utf8)
            bytes.append(body)
            connection.send(content: bytes, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}

@Suite(.timeLimit(.minutes(1)))
struct FLSTransferTests {
    @Test func downloadsWithoutOverwritingExistingFile() async throws {
        let body = Data(repeating: 42, count: 128_000)
        let server = try FLSLoopbackServer { _ in (200, [:], body) }
        let baseURL = try await server.start()
        defer { server.stop() }
        let client = FLSNetworkClient(configuration: try FLSNetworkConfiguration(baseURL: baseURL))
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destination) }
        let result = try await client.download(FLSRequest(path: "file"), to: destination)
        #expect(result.fileURL == destination)
        #expect(result.response.statusCode == 200)
        #expect(try Data(contentsOf: destination) == body)
        do {
            _ = try await client.download(FLSRequest(path: "file"), to: destination)
            Issue.record("Existing download destination must not be overwritten")
        } catch FLSNetworkError.file { }
        #expect(try Data(contentsOf: destination) == body)
    }

    @Test func failedDownloadDoesNotCreateDestination() async throws {
        let server = try FLSLoopbackServer { _ in (403, [:], Data("denied".utf8)) }
        let baseURL = try await server.start()
        defer { server.stop() }
        let client = FLSNetworkClient(configuration: try FLSNetworkConfiguration(baseURL: baseURL))
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            _ = try await client.download(FLSRequest(path: "file"), to: destination)
            Issue.record("Expected HTTP failure")
        } catch FLSNetworkError.httpStatus(let response) { #expect(response.statusCode == 403) }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func doesNotFollowRedirects() async throws {
        let server = try FLSLoopbackServer { request in
            #expect(request.hasPrefix("GET /redirect "))
            return (302, ["Location": "/unexpected"], Data())
        }
        let baseURL = try await server.start()
        defer { server.stop() }
        let client = FLSNetworkClient(configuration: try FLSNetworkConfiguration(baseURL: baseURL))
        do {
            _ = try await client.execute(FLSRequest(path: "redirect"))
            Issue.record("Expected redirect status error")
        } catch FLSNetworkError.httpStatus(let response) { #expect(response.statusCode == 302) }
    }
}
