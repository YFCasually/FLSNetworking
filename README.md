# FLSNetworking

面向 iOS 17+ 的独立 Swift 网络组件，以 Alamofire 为传输实现，公开接口使用 Foundation、Codable 和 Swift Concurrency。包名、模块名均为 `FLSNetworking`，自定义类型统一使用 `FLS` 前缀，与接入项目的命名规范独立。

## 环境与依赖

- iOS 17+；支持 macOS 13+，方便独立运行测试。
- Swift 6.0+ / Xcode 16+，启用 Swift 6 语言模式。
- 使用 SPM 管理依赖，Alamofire 版本范围为 `5.10.2..<5.11.0`。该范围用于保留 Swift 6.0 工具链兼容性，升级依赖时需同时检查其最低工具版本。
- 此版本不包含业务接口、登录状态、UI 或布局依赖。

## SPM 接入

在 Xcode 的 **File → Add Package Dependencies** 输入：

```text
https://github.com/YFCasually/FLSNetworking.git
```

当前初始交付使用 **Branch: main**，选择 `FLSNetworking` 产品。仓库尚未发布版本标签；需要稳定锁定时，可在 Xcode 中选择指定提交。

其他 Swift Package 的依赖声明：

```swift
.package(url: "https://github.com/YFCasually/FLSNetworking.git", branch: "main")
// 对应 target 的 dependencies：
.product(name: "FLSNetworking", package: "FLSNetworking")
```

接入后只需 `import FLSNetworking`，业务层无需导入 Alamofire。

## 可运行 Demo

打开 [`Examples/FLSNetworkingDemo/FLSNetworkingDemo.xcodeproj`](Examples/FLSNetworkingDemo/FLSNetworkingDemo.xcodeproj)，选择 iOS 17+ 模拟器后运行。Demo 使用 SwiftUI，通过本地 SPM 依赖引用组件，内置仅监听回环地址的模拟服务，运行时无需后端或 API Key。

覆盖 GET、JSON POST、业务响应解析、文件上传/下载及进度、HTTP/业务错误、Task 取消。运行步骤与代码入口见 [Demo 使用说明](Examples/FLSNetworkingDemo/README.md)。Demo UI 和模拟服务均不编入 `FLSNetworking` 产品。

## 创建客户端

```swift
import Foundation
import FLSNetworking

actor FLSTokenStore {
    private var token: String?

    func update(_ value: String?) { token = value }

    func headers() -> [String: String] {
        guard let token else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }
}

func makeClient(baseURL: URL, tokenStore: FLSTokenStore) throws -> FLSNetworkClient {
    let configuration = try FLSNetworkConfiguration(
        baseURL: baseURL,
        timeout: 30,
        defaultHeaders: ["Accept": "application/json"],
        headerProvider: { await tokenStore.headers() },
        requestAdapter: { request in
            var request = request
            request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
            return request
        }
    )
    return FLSNetworkClient(configuration: configuration)
}
```

每个客户端持有独立 Session。由 App 的依赖容器创建并注入，按环境创建不同实例。需要 Mock 时依赖 `any FLSHTTPClient`；该协议定义普通请求，文件传输使用 `FLSNetworkClient`。

`headerProvider` 每次 API 请求执行一次，读取当时的令牌。覆盖顺序为默认 Header → 动态 Header → Endpoint Header，之后执行 `requestAdapter`。签名、加密或额外公共字段可由 App 在 Adapter 中实现；Adapter 必须保持原协议、主机和端口。

## 普通请求

```swift
struct FLSExampleItem: Decodable, Sendable {
    let id: String
    let title: String
}

func loadItems(client: any FLSHTTPClient) async throws -> [FLSExampleItem] {
    try await client.request(
        FLSRequest(path: "items", queryItems: [URLQueryItem(name: "page", value: "1")]),
        as: [FLSExampleItem].self
    )
}

struct FLSCreateInput: Encodable {
    let title: String
}

func createItem(client: any FLSHTTPClient) async throws -> FLSExampleItem {
    let body = try FLSRequestBody.json(FLSCreateInput(title: "示例"))
    return try await client.request(
        FLSRequest(path: "items", method: .post, body: body),
        as: FLSExampleItem.self
    )
}
```

`baseURL` 中的基础路径会保留。例如 `https://example.com/api/v1/` 与 `items` 拼接为 `/api/v1/items`。Endpoint 只传相对路径，查询参数使用 `queryItems`；不接受绝对地址、路径跳转、内嵌查询或 fragment。路径两端的 `/` 会归一化。

请求体支持 `.json`、`.form`、`.raw`，GET/HEAD 必须通过查询参数传值。自定义 Header 中已有 Content-Type 时优先保留。模型字段映射通过 Codable 或每次创建的自定义 JSONDecoder 实现：

```swift
func loadItem(client: any FLSHTTPClient) async throws -> FLSExampleItem {
    try await client.request(FLSRequest(path: "items/1"), as: FLSExampleItem.self) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
```

## 响应方式与错误

三种响应方式由调用方明确选择，不自动猜测数据结构：

| 方法 | 用途 |
| --- | --- |
| `execute` | 获取原始 Data、状态码、Header；允许空的 2xx 响应 |
| `request` | 将完整 JSON 解码为模型 |
| `requestPayload` | 从 `{code, message/msg, data}` 结构中获取 data；显式传入成功码 |

```swift
func loadWrappedItem(client: any FLSHTTPClient) async throws -> FLSExampleItem {
    try await client.requestPayload(
        FLSRequest(path: "items/1"), as: FLSExampleItem.self,
        successCodes: ["0", "200"] // 由当前后端协议决定，不是组件内置约定。
    )
}

func deleteItem(client: any FLSHTTPClient) async throws {
    _ = try await client.execute(FLSRequest(path: "items/1", method: .delete))
}
```

`code` 支持字符串和整数，统一暴露为字符串。`requestPayload` 先检查业务码，再解码成功模型，避免错误响应的 data 类型不同而掩盖业务错误。直接解码 `FLSAPIResponse<T>` 时会同时解码 T，适合已明确响应结构的调用方。成功但 data 缺失/null、空响应的模型解码会抛出 `emptyResponse`。

```swift
func handleRequest(client: any FLSHTTPClient) async {
    do {
        _ = try await client.execute(FLSRequest(path: "health"))
    } catch is CancellationError {
        // 取消属于调用生命周期，App 按需忽略。
    } catch FLSNetworkError.httpStatus(let response) {
        print(response.statusCode)
        // 普通请求的原始错误体可从 response.data 获取。
    } catch FLSNetworkError.business(let code, let message) {
        print(code, message)
    } catch {
        // 包括 transport、encoding、decoding、invalidRequest、file 等错误。
    }
}
```

只有 HTTP 2xx 被视为传输成功；组件不自动刷新 Token、不自动重试，也不提前根据网络可达性拒绝请求。3xx 不自动跟随，按 `httpStatus` 返回。取消 Swift Task 会取消对应 Alamofire 请求，并以 `CancellationError` 传播。

## 文件上传与下载

```swift
func uploadFile(client: FLSNetworkClient, fileURL: URL) async throws {
    _ = try await client.upload(
        fileURL: fileURL,
        to: FLSRequest(path: "files", method: .post, headers: ["Content-Type": "application/octet-stream"]),
        progress: { progress in
            print(progress.completedBytes, progress.totalBytes)
        }
    )
}

func uploadToStorage(client: FLSNetworkClient, fileURL: URL, signedURL: URL) async throws {
    _ = try await client.upload(
        fileURL: fileURL,
        to: signedURL,
        method: .put,
        headers: ["Content-Type": "application/octet-stream"]
    )
}

func downloadFile(client: FLSNetworkClient, destination: URL) async throws -> URL {
    let result = try await client.download(FLSRequest(path: "files/1"), to: destination)
    return result.fileURL
}
```

文件上传使用本地普通文件 URL，通过文件流传输。API 上传使用公共 Header 和 Adapter；预签名 URL 上传保留原始 URL，不注入 API 默认 Header、令牌或 Adapter。组件还禁用 Session 隐式 Cookie、URL 凭据、缓存与附加 Header；签名上传所需 Header 由调用方显式提供。

下载先写入临时文件，确认 HTTP 2xx 后移动到目标文件。目标父目录由调用方预先创建，不覆盖已有文件，失败时清理临时文件。下载响应的 `data` 始终为空（包括 HTTP 错误），避免将文件内容加载到内存；通过状态码和 Header 判断失败。

进度回调在后台串行队列触发，`fractionCompleted` 在总大小未知时为 nil。更新 SwiftUI 状态时切换至 `MainActor`。组件未包含后台传输恢复、断点续传、multipart、SSE 或 WebSocket。

## 日志与组件边界

`logger` 默认关闭。启用后仅返回 requestID、HTTP 方法、主机、状态码、耗时和结果；不记录路径、查询、Header、请求体或响应体。日志反映传输及 HTTP 结果，业务码校验和模型解码发生在其后。请求构造失败不会产生传输日志。回调可在非主线程执行，调用方需要自行保证线程安全。

提取旧网络层中的 Endpoint、请求配置、统一错误与文件传输职责，业务登录、成功码、加密协议、上传签名获取、媒体信息及 UI 提示由接入 App 管理。组件没有全局单例，也没有绑定 Vograin 的 VG 类型。

## 目录与命名

```text
Sources/FLSNetworking/
  Client/         客户端协议、传输实现
  Configuration/  环境、Header 和适配配置
  Request/        Endpoint、HTTP 方法、请求体
  Response/       原始响应、可选业务响应结构
  Errors/         组件错误
  Transfer/       文件传输结果与进度
  Logging/        安全日志事件
  Internal/       包内请求构造
Tests/FLSNetworkingTests/
```

自定义类型使用 `FLS`，文件按主要类型命名，目录不加前缀，属性及方法采用 lowerCamelCase。系统扩展如未来确需避免重名，使用 `fls_`；不使用接入项目的 `vg_`。公开 API 不暴露 Alamofire 类型，不向组件内添加业务接口或服务端地址。

## 验证

```bash
swift test
swift build -c release
xcodebuild -scheme FLSNetworking -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

测试包含 URLProtocol 模拟传输和仅监听本机回环地址的 HTTP 服务器，不依赖外部业务服务。覆盖请求编码、Header 覆盖、响应解析、HTTP/业务错误、Task 取消、签名上传鉴权隔离、重定向和下载防覆盖。GitHub Actions 使用 Xcode 16.4 执行包测试、Release 构建及 iOS 模拟器构建；具体运行结果见 Actions。
