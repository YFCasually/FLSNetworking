import Foundation

/// Optional convenience for explicit {code, message/msg, data} APIs.
/// Other response formats should use FLSHTTPClient.request(_:as:decoder:).
public struct FLSAPIResponse<Payload: Decodable & Sendable>: Decodable, Sendable {
    public let code: String
    public let message: String
    public let data: Payload?

    private enum CodingKeys: String, CodingKey {
        case code, message, msg, data
    }

    public init(from decoder: any Decoder) throws {
        let status = try FLSAPIStatus(from: decoder)
        code = status.code
        message = status.message
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent(Payload.self, forKey: .data)
    }

    public func validated(successCodes: Set<String>) throws -> Self {
        guard successCodes.contains(code) else {
            throw FLSNetworkError.business(code: code, message: message)
        }
        return self
    }

    public func payload(successCodes: Set<String>) throws -> Payload {
        _ = try validated(successCodes: successCodes)
        guard let data else { throw FLSNetworkError.emptyResponse }
        return data
    }
}

struct FLSAPIStatus: Decodable, Sendable {
    let code: String
    let message: String

    private enum CodingKeys: String, CodingKey { case code, message, msg }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(String.self, forKey: .code) {
            code = value
        } else {
            code = String(try container.decode(Int.self, forKey: .code))
        }
        message = try container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .msg)
            ?? ""
    }

    func validate(successCodes: Set<String>) throws {
        guard successCodes.contains(code) else {
            throw FLSNetworkError.business(code: code, message: message)
        }
    }
}
