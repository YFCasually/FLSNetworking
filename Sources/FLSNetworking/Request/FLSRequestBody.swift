import Foundation

/// Explicit body encoding. GET/HEAD requests must use query items instead.
public enum FLSRequestBody: Sendable {
    case none
    case json(Data)
    case form([URLQueryItem])
    case raw(Data, contentType: String?)

    public static func json<T: Encodable>(_ value: T, encoder: JSONEncoder = JSONEncoder()) throws -> Self {
        do {
            return .json(try encoder.encode(value))
        } catch {
            throw FLSNetworkError.encoding(underlying: error)
        }
    }

    func apply(to request: inout URLRequest) throws {
        switch self {
        case .none:
            return
        case .json(let data):
            request.httpBody = data
            setContentType("application/json", on: &request)
        case .form(let items):
            let encoded = items.map { item in
                "\(formEncode(item.name))=\(formEncode(item.value ?? ""))"
            }.joined(separator: "&")
            request.httpBody = Data(encoded.utf8)
            setContentType("application/x-www-form-urlencoded; charset=utf-8", on: &request)
        case .raw(let data, let contentType):
            request.httpBody = data
            if let contentType { setContentType(contentType, on: &request) }
        }
        if request.httpMethod == "GET" || request.httpMethod == "HEAD" {
            throw FLSNetworkError.invalidRequest("GET and HEAD bodies are unsupported; use queryItems.")
        }
    }

    private func setContentType(_ value: String, on request: inout URLRequest) {
        if request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue(value, forHTTPHeaderField: "Content-Type")
        }
    }

    private func formEncode(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._*"))
        return (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)
            .replacingOccurrences(of: "%20", with: "+")
    }
}
