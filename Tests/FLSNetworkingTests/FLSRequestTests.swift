import Foundation
import Testing
@testable import FLSNetworking

struct FLSRequestTests {
    @Test func preservesBasePathAndQueryValues() async throws {
        let config = try FLSNetworkConfiguration(baseURL: #require(URL(string: "https://example.com/api/v1/")))
        let request = try await FLSRequestBuilder.build(FLSRequest(
            path: "/items", queryItems: [.init(name: "q", value: "中文 &+=?"), .init(name: "id", value: "1"), .init(name: "id", value: "2")]
        ), configuration: config)
        let url = try #require(request.url)
        #expect(url.path == "/api/v1/items")
        #expect(url.absoluteString.contains("%2B"))
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "中文 &+=?")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.count == 3)
    }

    @Test(arguments: ["https://other.example.com/x", "//other.example.com/x", "../x", "%2e%2e/x", "%252e%252e/x", "x?q=1", "x#fragment", "x\\y"])
    func rejectsUnsafePaths(_ path: String) async throws {
        let config = try FLSNetworkConfiguration(baseURL: #require(URL(string: "https://example.com/api")))
        await #expect(throws: FLSNetworkError.self) {
            try await FLSRequestBuilder.build(FLSRequest(path: path), configuration: config)
        }
    }

    @Test func appliesHeaderPrecedenceAndAdapter() async throws {
        let config = try FLSNetworkConfiguration(
            baseURL: #require(URL(string: "https://example.com")),
            defaultHeaders: ["Authorization": "default", "X-Default": "yes"],
            headerProvider: { ["authorization": "dynamic", "X-Dynamic": "yes"] },
            requestAdapter: { request in
                var request = request
                request.setValue("adapted", forHTTPHeaderField: "X-Adapter")
                return request
            }
        )
        let request = try await FLSRequestBuilder.build(FLSRequest(path: "x", headers: ["AUTHORIZATION": "endpoint"]), configuration: config)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "endpoint")
        #expect(request.value(forHTTPHeaderField: "X-Default") == "yes")
        #expect(request.value(forHTTPHeaderField: "X-Dynamic") == "yes")
        #expect(request.value(forHTTPHeaderField: "X-Adapter") == "adapted")
    }

    @Test func rejectsCrossOriginAdapter() async throws {
        let config = try FLSNetworkConfiguration(baseURL: #require(URL(string: "https://example.com")), requestAdapter: { request in
            var request = request
            request.url = URL(string: "https://other.example.com")
            return request
        })
        await #expect(throws: FLSNetworkError.self) {
            try await FLSRequestBuilder.build(FLSRequest(path: "x"), configuration: config)
        }
    }

    @Test func encodesJSONAndFormWithoutChangingHeaders() async throws {
        let config = try FLSNetworkConfiguration(baseURL: #require(URL(string: "https://example.com")))
        let json = try await FLSRequestBuilder.build(FLSRequest(path: "x", method: .post, body: .json(["value": "中文"])), configuration: config)
        #expect(json.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try JSONDecoder().decode([String: String].self, from: #require(json.httpBody)) == ["value": "中文"])
        let form = try await FLSRequestBuilder.build(FLSRequest(
            path: "x", method: .post, headers: ["Content-Type": "custom"],
            body: .form([.init(name: "q", value: "a +&="), .init(name: "empty", value: nil)])
        ), configuration: config)
        #expect(String(data: try #require(form.httpBody), encoding: .utf8) == "q=a+%2B%26%3D&empty=")
        #expect(form.value(forHTTPHeaderField: "Content-Type") == "custom")
        #expect(form.value(forHTTPHeaderField: "q") == nil)
    }

    @Test(arguments: [FLSHTTPMethod.get, .head])
    func rejectsBodiesOnReadMethods(_ method: FLSHTTPMethod) async throws {
        let config = try FLSNetworkConfiguration(baseURL: #require(URL(string: "https://example.com")))
        await #expect(throws: FLSNetworkError.self) {
            try await FLSRequestBuilder.build(FLSRequest(path: "x", method: method, body: .raw(Data(), contentType: nil)), configuration: config)
        }
    }

    @Test(arguments: ["file:///tmp/file", "https://user:password@example.com", "https://example.com?token=x", "https://example.com#x"])
    func rejectsInvalidConfiguration(_ value: String) throws {
        let url = try #require(URL(string: value))
        #expect(throws: FLSNetworkError.self) { try FLSNetworkConfiguration(baseURL: url) }
    }

    @Test func rejectsInvalidTimeout() throws {
        let url = try #require(URL(string: "https://example.com"))
        for timeout in [0.0, -1.0, .infinity, .nan] {
            #expect(throws: FLSNetworkError.self) { try FLSNetworkConfiguration(baseURL: url, timeout: timeout) }
        }
    }
}
