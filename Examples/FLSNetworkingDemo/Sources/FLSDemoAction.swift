import Foundation

enum FLSDemoAction: String, CaseIterable, Identifiable, Sendable {
    case get, post, payload, upload, download, httpError, businessError, slow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .get: "GET 请求"
        case .post: "JSON POST"
        case .payload: "业务响应解析"
        case .upload: "文件上传"
        case .download: "文件下载"
        case .httpError: "HTTP 错误"
        case .businessError: "业务错误"
        case .slow: "延迟请求 / 取消"
        }
    }

    var symbol: String {
        switch self {
        case .get, .post, .payload: "arrow.left.arrow.right"
        case .upload: "arrow.up.doc"
        case .download: "arrow.down.doc"
        case .httpError, .businessError: "exclamationmark.triangle"
        case .slow: "hourglass"
        }
    }
}

struct FLSDemoMessage: Decodable, Sendable {
    let method: String
    let message: String
    let receivedBytes: Int?

    var summary: String {
        var text = "method: \(method)\nmessage: \(message)"
        if let receivedBytes { text += "\nreceivedBytes: \(receivedBytes)" }
        return text
    }
}

struct FLSDemoPostBody: Encodable, Sendable {
    let message: String
}
