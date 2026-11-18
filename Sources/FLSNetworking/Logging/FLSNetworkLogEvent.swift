import Foundation

/// Minimal telemetry. No request/response contents or credential-bearing URLs are exposed.
public struct FLSNetworkLogEvent: Sendable {
    public let requestID: UUID
    public let method: String
    public let host: String
    public let statusCode: Int?
    public let duration: TimeInterval
    public let outcome: FLSNetworkLogOutcome
}

public enum FLSNetworkLogOutcome: String, Sendable {
    case success
    case failure
    case cancelled
}
