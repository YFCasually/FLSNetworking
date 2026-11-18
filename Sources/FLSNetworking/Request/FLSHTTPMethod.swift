/// HTTP methods supported by the component, without exposing Alamofire types.
public enum FLSHTTPMethod: String, Sendable, CaseIterable {
    case get = "GET"
    case head = "HEAD"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case options = "OPTIONS"
}
