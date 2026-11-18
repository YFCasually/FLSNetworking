# FLSNetworking SwiftUI Demo

独立的 iOS 17+ 示例工程，通过本地 SPM 依赖引用仓库根目录的 `FLSNetworking`。组件类型继续使用 `FLS` 前缀。

## 运行

1. 克隆完整仓库，使用 Xcode 16+ 打开 `FLSNetworkingDemo.xcodeproj`。
2. 等待 SPM 解析 Alamofire，选择 `FLSNetworkingDemo` scheme 和 iOS 17+ 模拟器。
3. 按 `⌘R` 启动，点击页面上的示例按钮。`⌘U` 可执行覆盖全部示例与取消操作的 UI 冒烟测试。

真机运行需要在 Signing & Capabilities 中选择自己的开发团队，必要时修改 Bundle Identifier。

首次解析 SPM 需要联网；运行时内置模拟服务只监听 `127.0.0.1` 的随机端口，无需后端、账号或 API Key。请求实际经过 `FLSNetworkClient → Alamofire → URLSession → 本地 HTTP 服务`，上传和下载均使用真实临时文件。Info.plist 仅允许本地网络 HTTP，不开放全局 ATS 例外。

## 示例内容

| 按钮 | 展示内容 | 预期结果 |
| --- | --- | --- |
| GET 请求 | 查询参数、Codable 解码 | `Hello FLSNetworking` |
| JSON POST | Encodable 请求体 | 回显 `Hello FLSNetworking` |
| 业务响应解析 | 显式解析 `{code,message,data}`，成功码由调用方指定 | 业务数据解析成功 |
| 文件上传 | PUT 上传 256 KiB 文件、进度回调 | 服务端接收 262144 bytes |
| 文件下载 | 下载到新路径、进度回调、内容校验 | 校验通过，临时文件自动清理 |
| HTTP 错误 | 捕获 `FLSNetworkError.httpStatus` 并读取错误响应 | HTTP 503 |
| 业务错误 | HTTP 200 下捕获 `FLSNetworkError.business` | code 401 |
| 延迟请求 / 取消 | 10 秒延迟，调用 `Task.cancel()` | `CancellationError`；也可等待正常完成 |

本地传输很快，进度可能直接跳到 100%。错误按钮主动制造失败，用于展示调用方如何处理错误。

## 阅读顺序

- `Sources/FLSDemoModel.swift`：组件调用、Task 生命周期、主线程状态与错误处理。
- `Sources/FLSDemoView.swift`：SwiftUI + Observation 绑定。
- `Sources/FLSDemoAction.swift`：演示选项及请求/响应模型。
- `Sources/FLSDemoServer.swift`：仅限 Demo 的固定 HTTP 测试服务，不会编入组件产品，不作为生产服务器复用。
- `UITests/FLSDemoUITests.swift`：模拟器端到端冒烟测试。

工程文件已提交，无需安装 XcodeGen。维护者修改 `project.yml` 后，可在本目录执行 `xcodegen generate` 重新生成工程；该工具不属于 App 或组件的依赖。
