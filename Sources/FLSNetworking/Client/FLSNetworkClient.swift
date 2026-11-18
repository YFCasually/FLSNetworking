import Alamofire
import Foundation

/// Instance-scoped HTTP client. Session and immutable configuration are safe to share across tasks.
public final class FLSNetworkClient: FLSHTTPClient, Sendable {
    private let configuration: FLSNetworkConfiguration
    private let session: Session
    private let progressQueue = DispatchQueue(label: "FLSNetworking.progress")

    /// Copies the session configuration and disables ambient cookies, cache and credentials.
    public init(
        configuration: FLSNetworkConfiguration,
        sessionConfiguration: URLSessionConfiguration = .ephemeral
    ) {
        self.configuration = configuration
        // Disable ambient cookies/cache/credentials. API authentication comes from explicit headers.
        let transport = (sessionConfiguration.copy() as? URLSessionConfiguration) ?? .ephemeral
        transport.httpCookieStorage = nil
        transport.httpShouldSetCookies = false
        transport.urlCredentialStorage = nil
        transport.urlCache = nil
        transport.requestCachePolicy = .reloadIgnoringLocalCacheData
        transport.httpAdditionalHeaders = nil
        self.session = Session(configuration: transport)
    }

    public func execute(_ endpoint: any FLSEndpoint) async throws -> FLSHTTPResponse {
        let request = try await FLSRequestBuilder.build(endpoint, configuration: configuration)
        return try await perform(session.request(request), request: request)
    }

    /// Streams a local file to an API endpoint without reading the whole file into memory.
    public func upload(
        fileURL: URL,
        to endpoint: any FLSEndpoint,
        progress: (@Sendable (FLSTransferProgress) -> Void)? = nil
    ) async throws -> FLSHTTPResponse {
        let request = try await FLSRequestBuilder.build(endpoint, configuration: configuration)
        return try await upload(fileURL: fileURL, request: request, progress: progress)
    }

    /// Signed URL upload. No API headers, token provider or request adapter are applied.
    /// Supply only the exact headers required by the object-storage signature.
    public func upload(
        fileURL: URL,
        to signedURL: URL,
        method: FLSHTTPMethod = .put,
        headers: [String: String] = [:],
        progress: (@Sendable (FLSTransferProgress) -> Void)? = nil
    ) async throws -> FLSHTTPResponse {
        try Task.checkCancellation()
        try FLSRequestBuilder.validateHTTPURL(signedURL)
        guard signedURL.fragment == nil else { throw FLSNetworkError.invalidRequest("Signed URL must not have a fragment.") }
        var request = URLRequest(url: signedURL, timeoutInterval: configuration.timeout)
        request.httpMethod = method.rawValue
        request.allHTTPHeaderFields = headers
        return try await upload(fileURL: fileURL, request: request, progress: progress)
    }

    /// Downloads to a new file. Never overwrites an existing destination.
    /// Temporary files are removed on HTTP failure, cancellation or move failure.
    public func download(
        _ endpoint: any FLSEndpoint,
        to destination: URL,
        progress: (@Sendable (FLSTransferProgress) -> Void)? = nil
    ) async throws -> FLSDownloadResult {
        guard destination.isFileURL else { throw FLSNetworkError.invalidRequest("Download destination must be a file URL.") }
        let request = try await FLSRequestBuilder.build(endpoint, configuration: configuration)
        let download = session.download(request).redirect(using: Redirector(behavior: .doNotFollow))
        if let progress {
            download.downloadProgress(queue: progressQueue) { progress(FLSTransferProgress($0)) }
        }
        let started = Date()
        let requestID = UUID()
        let result = await download.serializingDownloadedFileURL(automaticallyCancelling: true).response
        defer { if let file = result.fileURL { try? FileManager.default.removeItem(at: file) } }
        do {
            try Task.checkCancellation()
            try checkTransportError(result.error)
            let response = try makeResponse(data: Data(), response: result.response)
            try validate(response)
            guard let temporaryFile = result.fileURL else { throw FLSNetworkError.invalidResponse }
            try Task.checkCancellation()
            do {
                try FileManager.default.moveItem(at: temporaryFile, to: destination)
            } catch {
                throw FLSNetworkError.file(underlying: error)
            }
            log(request, id: requestID, started: started, status: response.statusCode, outcome: .success)
            return FLSDownloadResult(fileURL: destination, response: response)
        } catch {
            log(request, id: requestID, started: started, status: result.response?.statusCode,
                outcome: error is CancellationError ? .cancelled : .failure)
            throw error
        }
    }

    private func upload(
        fileURL: URL,
        request: URLRequest,
        progress: (@Sendable (FLSTransferProgress) -> Void)?
    ) async throws -> FLSHTTPResponse {
        guard fileURL.isFileURL,
              (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              FileManager.default.isReadableFile(atPath: fileURL.path) else {
            throw FLSNetworkError.invalidRequest("Upload source must be a readable local file.")
        }
        guard !["GET", "HEAD"].contains(request.httpMethod?.uppercased() ?? ""),
              request.httpBody == nil, request.httpBodyStream == nil else {
            throw FLSNetworkError.invalidRequest("File upload requires a bodyless non-GET/HEAD request.")
        }
        try Task.checkCancellation()
        let upload = session.upload(fileURL, with: request)
        if let progress {
            upload.uploadProgress(queue: progressQueue) { progress(FLSTransferProgress($0)) }
        }
        return try await perform(upload, request: request)
    }

    private func perform(_ dataRequest: DataRequest, request: URLRequest) async throws -> FLSHTTPResponse {
        let started = Date()
        let requestID = UUID()
        let result = await dataRequest.redirect(using: Redirector(behavior: .doNotFollow))
            .serializingData(automaticallyCancelling: true, emptyResponseCodes: Set(100...599)).response
        do {
            try Task.checkCancellation()
            try checkTransportError(result.error)
            let response = try makeResponse(data: result.data ?? Data(), response: result.response)
            try validate(response)
            log(request, id: requestID, started: started, status: response.statusCode, outcome: .success)
            return response
        } catch {
            log(request, id: requestID, started: started, status: result.response?.statusCode,
                outcome: error is CancellationError ? .cancelled : .failure)
            throw error
        }
    }

    private func checkTransportError(_ error: AFError?) throws {
        guard let error else { return }
        if error.isExplicitlyCancelledError || (error.underlyingError as? URLError)?.code == .cancelled {
            throw CancellationError()
        }
        throw FLSNetworkError.transport(underlying: error)
    }

    private func makeResponse(data: Data, response: HTTPURLResponse?) throws -> FLSHTTPResponse {
        guard let response else { throw FLSNetworkError.invalidResponse }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields { headers[String(describing: key)] = String(describing: value) }
        return FLSHTTPResponse(data: data, statusCode: response.statusCode, headers: headers, url: response.url)
    }

    private func validate(_ response: FLSHTTPResponse) throws {
        guard (200...299).contains(response.statusCode) else { throw FLSNetworkError.httpStatus(response) }
    }

    private func log(
        _ request: URLRequest, id: UUID, started: Date, status: Int?, outcome: FLSNetworkLogOutcome
    ) {
        configuration.logger?(FLSNetworkLogEvent(
            requestID: id, method: request.httpMethod ?? "", host: request.url?.host ?? "",
            statusCode: status, duration: max(0, Date().timeIntervalSince(started)), outcome: outcome
        ))
    }
}
