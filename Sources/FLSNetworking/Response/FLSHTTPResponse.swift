import Foundation

public struct FLSHTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]
    public let url: URL?

    public init(data: Data, statusCode: Int, headers: [String: String] = [:], url: URL? = nil) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
        self.url = url
    }

    public func header(named name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public func decode<T: Decodable & Sendable>(
        _ type: T.Type = T.self,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        guard !data.isEmpty else { throw FLSNetworkError.emptyResponse }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw FLSNetworkError.decoding(underlying: error)
        }
    }
}
