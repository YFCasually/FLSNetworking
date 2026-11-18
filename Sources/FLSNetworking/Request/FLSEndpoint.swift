import Foundation

/// An endpoint describes one request. Business endpoints belong to the consuming app.
public protocol FLSEndpoint: Sendable {
    /// A path relative to the configured base URL. No host, query, fragment or traversal.
    var path: String { get }
    var method: FLSHTTPMethod { get }
    var queryItems: [URLQueryItem] { get }
    var headers: [String: String] { get }
    var body: FLSRequestBody { get }
    var timeout: TimeInterval? { get }
}

public extension FLSEndpoint {
    var method: FLSHTTPMethod { .get }
    var queryItems: [URLQueryItem] { [] }
    var headers: [String: String] { [:] }
    var body: FLSRequestBody { .none }
    var timeout: TimeInterval? { nil }
}

/// A ready-to-use endpoint for callers that do not need their own enum or struct.
public struct FLSRequest: FLSEndpoint {
    public let path: String
    public let method: FLSHTTPMethod
    public let queryItems: [URLQueryItem]
    public let headers: [String: String]
    public let body: FLSRequestBody
    public let timeout: TimeInterval?

    public init(
        path: String,
        method: FLSHTTPMethod = .get,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: FLSRequestBody = .none,
        timeout: TimeInterval? = nil
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}
