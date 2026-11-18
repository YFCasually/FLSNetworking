import Foundation

enum FLSRequestBuilder {
    static func build(_ endpoint: any FLSEndpoint, configuration: FLSNetworkConfiguration) async throws -> URLRequest {
        try Task.checkCancellation()
        guard let path = URLComponents(string: endpoint.path),
              path.scheme == nil, path.host == nil, path.query == nil, path.fragment == nil,
              !endpoint.path.hasPrefix("//"), !endpoint.path.contains("\\") else {
            throw FLSNetworkError.invalidRequest("Endpoint must contain only a relative path.")
        }
        let decodedPath = path.path
        guard !decodedPath.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              !decodedPath.contains("\\"), !decodedPath.contains("%") else {
            throw FLSNetworkError.invalidRequest("Endpoint path traversal and nested escaping are unsupported.")
        }
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw FLSNetworkError.invalidRequest("Base URL cannot be represented.")
        }
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let relativePath = path.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = "/" + [basePath, relativePath].filter { !$0.isEmpty }.joined(separator: "/")
        components.queryItems = endpoint.queryItems.isEmpty ? nil : endpoint.queryItems
        // Many servers interpret a literal + as a space when parsing query parameters.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw FLSNetworkError.invalidRequest("Endpoint URL cannot be represented.") }

        let timeout = endpoint.timeout ?? configuration.timeout
        guard timeout.isFinite, timeout > 0 else { throw FLSNetworkError.invalidRequest("Timeout must be positive.") }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = endpoint.method.rawValue
        apply(configuration.defaultHeaders, to: &request)
        if let provider = configuration.headerProvider { apply(try await provider(), to: &request) }
        apply(endpoint.headers, to: &request)
        try endpoint.body.apply(to: &request)
        if let adapter = configuration.requestAdapter { request = try await adapter(request) }
        try Task.checkCancellation()
        guard let finalURL = request.url else { throw FLSNetworkError.invalidRequest("Adapter removed the request URL.") }
        try validateHTTPURL(finalURL)
        guard sameOrigin(url, finalURL) else {
            throw FLSNetworkError.invalidRequest("Adapter must not change the request origin.")
        }
        guard finalURL.fragment == nil, request.timeoutInterval.isFinite, request.timeoutInterval > 0 else {
            throw FLSNetworkError.invalidRequest("Adapted requests require a positive timeout and no URL fragment.")
        }
        if ["GET", "HEAD"].contains(request.httpMethod?.uppercased() ?? ""),
           request.httpBody != nil || request.httpBodyStream != nil {
            throw FLSNetworkError.invalidRequest("Adapted GET and HEAD requests must not contain a body.")
        }
        return request
    }

    static func validateHTTPURL(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            throw FLSNetworkError.invalidRequest("An HTTP(S) URL without embedded credentials is required.")
        }
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        func port(_ url: URL) -> Int { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased() && port(lhs) == port(rhs)
    }

    private static func apply(_ headers: [String: String], to request: inout URLRequest) {
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
    }
}
