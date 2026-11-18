import SwiftUI

struct FLSDemoView: View {
    @State private var model = FLSDemoModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("本地模拟服务 · 无需配置后端")
                        .font(.headline)
                    Text(model.serverAddress)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(FLSDemoAction.allCases) { action in
                            Button { model.run(action) } label: {
                                Label(action.title, systemImage: action.symbol)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!model.isReady || model.isRunning)
                            .accessibilityIdentifier("action-\(action.rawValue)")
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.status)
                            .font(.headline)
                            .accessibilityIdentifier("status")
                        if model.isRunning {
                            if let fraction = model.progress {
                                ProgressView(value: fraction)
                                Text("传输进度 \(Int(fraction * 100))%")
                                    .font(.caption)
                            } else {
                                ProgressView()
                            }
                            Button("取消当前请求", role: .destructive) { model.cancel() }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("cancel")
                        }
                        Text(model.result)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("result")
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))

                    Text("错误示例会主动返回失败；点击“延迟请求 / 取消”后可验证 Task 取消。上传和下载使用临时文件，完成后自动清理。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("FLSNetworking")
            .task { await model.start() }
        }
    }
}
