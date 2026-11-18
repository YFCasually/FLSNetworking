import FLSNetworking
import Foundation
import Observation

@MainActor
@Observable
final class FLSDemoModel {
    private(set) var serverAddress = "正在启动本地服务…"
    private(set) var isReady = false
    private(set) var isRunning = false
    private(set) var status = "准备中"
    private(set) var result = "请选择一个示例。"
    private(set) var progress: Double?

    @ObservationIgnored private var server: FLSDemoServer?
    @ObservationIgnored private var client: FLSNetworkClient?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var operationID: UUID?

    func start() async {
        guard server == nil else { return }
        do {
            let server = try FLSDemoServer()
            self.server = server
            let baseURL = try await server.start()
            client = FLSNetworkClient(configuration: try FLSNetworkConfiguration(baseURL: baseURL))
            serverAddress = baseURL.absoluteString
            isReady = true
            status = "就绪"
        } catch {
            server?.stop()
            server = nil
            status = "启动失败"
            result = error.localizedDescription
        }
    }

    func run(_ action: FLSDemoAction) {
        guard let client, !isRunning else { return }
        let id = UUID()
        operationID = id
        isRunning = true
        progress = nil
        status = "执行中：\(action.title)"
        result = action == .slow ? "服务端将延迟 10 秒响应，可点击取消。" : "等待响应…"
        operation = Task { [weak self] in
            guard let self else { return }
            defer {
                isRunning = false
                operationID = nil
                operation = nil
            }
            do {
                result = try await perform(action, client: client, id: id)
                status = "完成：\(action.title)"
            } catch is CancellationError {
                status = "已取消"
                result = "捕获 CancellationError，底层网络请求同步取消。"
            } catch FLSNetworkError.httpStatus(let response) {
                status = "预期错误：HTTP \(response.statusCode)"
                result = "HTTP \(response.statusCode)\n" + String(decoding: response.data, as: UTF8.self)
            } catch FLSNetworkError.business(let code, let message) {
                status = "预期错误：业务 \(code)"
                result = "business code: \(code)\nmessage: \(message)"
            } catch {
                status = "请求失败"
                result = error.localizedDescription
            }
        }
    }

    func cancel() { operation?.cancel() }

    private func perform(_ action: FLSDemoAction, client: FLSNetworkClient, id: UUID) async throws -> String {
        switch action {
        case .get:
            let message = try await client.request(
                FLSRequest(path: "get", queryItems: [URLQueryItem(name: "source", value: "SwiftUI")]),
                as: FLSDemoMessage.self
            )
            return message.summary
        case .post:
            let request = FLSRequest(path: "post", method: .post,
                                     body: try .json(FLSDemoPostBody(message: "Hello FLSNetworking")))
            let message = try await client.request(request, as: FLSDemoMessage.self)
            return message.summary
        case .payload, .businessError:
            let path = action == .payload ? "payload" : "business-error"
            let message = try await client.requestPayload(
                FLSRequest(path: path), as: FLSDemoMessage.self, successCodes: ["0"]
            )
            return message.summary
        case .upload:
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: file) }
            try Data(repeating: 0x46, count: 262_144).write(to: file)
            let response = try await client.upload(
                fileURL: file,
                to: FLSRequest(path: "upload", method: .put, headers: ["Content-Type": "application/octet-stream"]),
                progress: progressHandler(id: id)
            )
            let message = try response.decode(FLSDemoMessage.self)
            guard message.receivedBytes == 262_144 else { throw FLSNetworkError.invalidResponse }
            return "上传成功\n" + message.summary
        case .download:
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: file) }
            let download = try await client.download(
                FLSRequest(path: "file"), to: file, progress: progressHandler(id: id)
            )
            let data = try Data(contentsOf: download.fileURL)
            guard data == Data(repeating: 0x46, count: 262_144) else { throw FLSNetworkError.invalidResponse }
            return "下载成功\nHTTP \(download.response.statusCode)\n已校验 \(data.count) bytes\n临时文件已自动清理。"
        case .httpError:
            _ = try await client.execute(FLSRequest(path: "status/503"))
            return "未返回预期错误"
        case .slow:
            let message = try await client.request(FLSRequest(path: "slow"), as: FLSDemoMessage.self)
            return message.summary
        }
    }

    private func progressHandler(id: UUID) -> @Sendable (FLSTransferProgress) -> Void {
        { [weak self] snapshot in
            Task { @MainActor [weak self] in
                guard let self, operationID == id else { return }
                progress = snapshot.fractionCompleted
            }
        }
    }
}
