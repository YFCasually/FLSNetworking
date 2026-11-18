import Foundation

/// Immutable configuration. Closures may run outside the main actor.
public struct FLSNetworkConfiguration: Sendable {
    public let baseURL: URL
    public let timeout: TimeInterval
    public let defaultHeaders: [String: String]
    /// Evaluated once for each API request, so tokens need not be captured at initialization.
    public let headerProvider: (@Sendable () async throws -> [String: String])?
    /// App-level wrapping, signing or encryption. Called once after request construction.
    public let requestAdapter: (@Sendable (URLRequest) async throws -> URLRequest)?
    /// Receives only metadata, without URL paths, queries, headers or bodies.
    public let logger: (@Sendable (FLSNetworkLogEvent) -> Void)?

    public init(
        baseURL: URL,
        timeout: TimeInterval = 30,
        defaultHeaders: [String: String] = [:],
        headerProvider: (@Sendable () async throws -> [String: String])? = nil,
        requestAdapter: (@Sendable (URLRequest) async throws -> URLRequest)? = nil,
        logger: (@Sendable (FLSNetworkLogEvent) -> Void)? = nil
    ) throws {
        try FLSRequestBuilder.validateHTTPURL(baseURL)
        guard baseURL.query == nil, baseURL.fragment == nil, timeout.isFinite, timeout > 0 else {
            throw FLSNetworkError.invalidRequest("Base URL must not contain a query/fragment; timeout must be positive.")
        }
        self.baseURL = baseURL
        self.timeout = timeout
        self.defaultHeaders = defaultHeaders
        self.headerProvider = headerProvider
        self.requestAdapter = requestAdapter
        self.logger = logger
    }
}
