import Foundation

/// The app can inject either FLSNetworkClient or a mock through this protocol.
public protocol FLSHTTPClient: Sendable {
    /// Returns any 2xx response, including an empty 204 or HEAD response.
    func execute(_ endpoint: any FLSEndpoint) async throws -> FLSHTTPResponse
}

public extension FLSHTTPClient {
    func request<T: Decodable & Sendable>(
        _ endpoint: any FLSEndpoint,
        as type: T.Type = T.self,
        decoder: @Sendable () -> JSONDecoder = { JSONDecoder() }
    ) async throws -> T {
        let response = try await execute(endpoint)
        try Task.checkCancellation()
        return try response.decode(type, decoder: decoder())
    }

    /// Explicit envelope parsing; success codes are owned by the consuming app.
    func requestPayload<T: Decodable & Sendable>(
        _ endpoint: any FLSEndpoint,
        as type: T.Type = T.self,
        successCodes: Set<String>,
        decoder: @Sendable () -> JSONDecoder = { JSONDecoder() }
    ) async throws -> T {
        let response = try await execute(endpoint)
        try Task.checkCancellation()
        // Error payloads often have a different shape. Check the code before decoding T.
        let status = try response.decode(FLSAPIStatus.self, decoder: decoder())
        try status.validate(successCodes: successCodes)
        let envelope = try response.decode(FLSAPIResponse<T>.self, decoder: decoder())
        return try envelope.payload(successCodes: successCodes)
    }
}
