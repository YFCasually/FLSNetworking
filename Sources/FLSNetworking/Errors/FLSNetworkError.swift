import Foundation

public enum FLSNetworkError: Error, LocalizedError, Sendable {
    case invalidRequest(String)
    case encoding(underlying: any Error)
    case transport(underlying: any Error)
    case invalidResponse
    /// Includes the response so callers can inspect HTTP errors without losing their payload.
    case httpStatus(FLSHTTPResponse)
    case decoding(underlying: any Error)
    case emptyResponse
    case business(code: String, message: String)
    case file(underlying: any Error)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let reason): "Invalid request: \(reason)"
        case .encoding: "Request encoding failed."
        case .transport: "Network transport failed."
        case .invalidResponse: "The server did not return an HTTP response."
        case .httpStatus(let response): "HTTP request failed (\(response.statusCode))."
        case .decoding: "Response decoding failed."
        case .emptyResponse: "The response contains no expected payload."
        case .business(let code, let message): "[\(code)] \(message)"
        case .file: "File transfer failed."
        }
    }
}
