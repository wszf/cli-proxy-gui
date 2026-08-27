import AppKit
import SwiftUI

enum ClientConfigurationExamples {
    static func claudeCode(nodeAddress: String, apiKey: String) -> String {
        let baseURL = ProxyNode.normalize(nodeAddress)

        return """
        # 仅对当前终端会话生效
        export ANTHROPIC_BASE_URL=\(shellQuoted(baseURL))
        export ANTHROPIC_AUTH_TOKEN=\(shellQuoted(apiKey))
        # 关闭更新、遥测等非必要外部请求；如需保留这些功能可删除此行
        export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1'

        # 如需固定模型，请替换为“查询当前可用模型”中的 ID
        # export ANTHROPIC_MODEL='claude-sonnet-4-6'

        claude
        """
    }

    static func claudeCodeSettings(nodeAddress: String, apiKey: String) -> String {
        let baseURL = ProxyNode.normalize(nodeAddress)

        return """
        {
          "$schema": "https://json.schemastore.org/claude-code-settings.json",
          "env": {
            "ANTHROPIC_BASE_URL": \(jsonQuoted(baseURL)),
            "ANTHROPIC_AUTH_TOKEN": \(jsonQuoted(apiKey)),
            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
          }
        }
        """
    }

    static func codexConfig(nodeAddress: String, apiKey: String) -> String {
        let baseURL = apiURL(nodeAddress: nodeAddress, path: "v1")

        return """
        model_provider = "cliproxyapi"
        model = "gpt-5.6-sol"
        model_reasoning_effort = "xhigh"
        plan_mode_reasoning_effort = "xhigh"

        [model_providers.cliproxyapi]
        name = "CLIProxyAPI"
        base_url = "\(tomlEscaped(baseURL))"
        wire_api = "responses"
        experimental_bearer_token = "\(tomlEscaped(apiKey))"
        stream_idle_timeout_ms = 900000
        """
    }

    static func availableModels(nodeAddress: String, apiKey: String) -> String {
        let url = apiURL(nodeAddress: nodeAddress, path: "v1/models")
        return """
        curl -sS \(shellQuoted(url)) \\
          -H \(shellQuoted("Authorization: Bearer \(apiKey)")) \
          | jq -r '.data[].id'
        """
    }

    static func responsesRequest(nodeAddress: String, apiKey: String) -> String {
        let url = apiURL(nodeAddress: nodeAddress, path: "v1/responses")
        return """
        curl -sS -X POST \(shellQuoted(url)) \\
          -H \(shellQuoted("Authorization: Bearer \(apiKey)")) \\
          -H 'Content-Type: application/json' \\
          -d '{
            "model": "gpt-5.6-sol",
            "input": "Reply with OK."
          }'
        """
    }

    static func claudeMessagesRequest(nodeAddress: String, apiKey: String) -> String {
        let url = apiURL(nodeAddress: nodeAddress, path: "v1/messages")
        return """
        curl -sS -X POST \(shellQuoted(url)) \\
          -H \(shellQuoted("Authorization: Bearer \(apiKey)")) \\
          -H 'Content-Type: application/json' \\
          -H 'anthropic-version: 2023-06-01' \\
          -d '{
            "model": "claude-sonnet-4-6",
            "max_tokens": 64,
            "messages": [{"role": "user", "content": "Reply with OK."}]
          }'
        """
    }

    private static func apiURL(nodeAddress: String, path: String) -> String {
        URL(string: ProxyNode.normalize(nodeAddress))?
            .appending(path: path)
            .absoluteString ?? "\(ProxyNode.normalize(nodeAddress))/\(path)"
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func jsonQuoted(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private static func tomlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

struct ClientConfigurationExamplesView: View {
    let node: ProxyNode
    let apiKeys: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedKeyIndex = 0
    @State private var selectedExampleTab: ExampleTab = .claudeCode
    @State private var copiedID: String?

    private enum ExampleTab: String, CaseIterable, Identifiable {
        case claudeCode
        case codex
        case api

        var id: Self { self }

        var title: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .codex: "Codex"
            case .api: "模型与 API 测试"
            }
        }

        var systemImage: String {
            switch self {
            case .claudeCode: "terminal"
            case .codex: "chevron.left.forwardslash.chevron.right"
            case .api: "network"
            }
        }
    }

    private var selectedKey: String {
        guard apiKeys.indices.contains(selectedKeyIndex) else { return "YOUR_API_KEY" }
        return apiKeys[selectedKeyIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    keySelection
                    exampleTabs
                    selectedExamples
                }
                .padding(20)
            }
        }
        .frame(width: 720, height: 660)
        .onChange(of: selectedKeyIndex) {
            copiedID = nil
        }
        .onChange(of: selectedExampleTab) {
            copiedID = nil
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("客户端配置示例")
                    .font(.title2.weight(.semibold))
                Text(node.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("完成") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    @ViewBuilder
    private var keySelection: some View {
        if apiKeys.isEmpty {
            Label("当前没有 API Key，示例将使用 YOUR_API_KEY 占位符。", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        } else {
            HStack {
                Text("示例使用")
                    .foregroundStyle(.secondary)
                Picker("API Key", selection: $selectedKeyIndex) {
                    ForEach(apiKeys.indices, id: \.self) { index in
                        Text("\(index + 1). \(masked(apiKeys[index]))").tag(index)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 280)
                Spacer()
                Label("复制内容包含完整 Key，请妥善保管", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var exampleTabs: some View {
        Picker("示例类型", selection: $selectedExampleTab) {
            ForEach(ExampleTab.allCases) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var selectedExamples: some View {
        switch selectedExampleTab {
        case .claudeCode:
            claudeCodeExamples
        case .codex:
            codexExamples
        case .api:
            apiExamples
        }
    }

    private var claudeCodeExamples: some View {
        exampleSection(
            title: "Claude Code",
            subtitle: "终端示例可直接执行；持久化示例请合并到 ~/.claude/settings.json，勿提交到项目仓库。",
            systemImage: "terminal",
            snippets: [
                Snippet(
                    id: "claude-terminal",
                    label: "终端（当前会话）",
                    content: ClientConfigurationExamples.claudeCode(
                        nodeAddress: node.address,
                        apiKey: selectedKey
                    )
                ),
                Snippet(
                    id: "claude-settings",
                    label: "~/.claude/settings.json（持久化）",
                    content: ClientConfigurationExamples.claudeCodeSettings(
                        nodeAddress: node.address,
                        apiKey: selectedKey
                    )
                )
            ]
        )
    }

    private var codexExamples: some View {
        exampleSection(
            title: "Codex",
            subtitle: "写入用户级 ~/.codex/config.toml 后即可使用，无需设置环境变量。",
            systemImage: "chevron.left.forwardslash.chevron.right",
            snippets: [
                Snippet(
                    id: "codex-config",
                    label: "~/.codex/config.toml（包含完整 Key）",
                    content: ClientConfigurationExamples.codexConfig(
                        nodeAddress: node.address,
                        apiKey: selectedKey
                    )
                ),
                Snippet(
                    id: "codex-permissions",
                    label: "保护配置文件",
                    content: "chmod 600 ~/.codex/config.toml"
                )
            ]
        )
    }

    private var apiExamples: some View {
        exampleSection(
            title: "模型与 API 测试",
            subtitle: "模型列表命令使用 jq 提取 ID；请求失败时可直接看到节点返回的错误。",
            systemImage: "network",
            snippets: [
                Snippet(
                    id: "available-models",
                    label: "查询当前可用模型",
                    content: ClientConfigurationExamples.availableModels(
                        nodeAddress: node.address,
                        apiKey: selectedKey
                    )
                ),
                Snippet(
                    id: "responses-request",
                    label: "Responses API",
                    content: ClientConfigurationExamples.responsesRequest(
                        nodeAddress: node.address,
                        apiKey: selectedKey
                    )
                ),
                Snippet(
                    id: "claude-messages-request",
                    label: "Claude Messages API",
                    content: ClientConfigurationExamples.claudeMessagesRequest(
                        nodeAddress: node.address,
                        apiKey: selectedKey
                    )
                )
            ]
        )
    }

    private func exampleSection(
        title: String,
        subtitle: String,
        systemImage: String,
        snippets: [Snippet]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(snippets) { snippet in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(snippet.label)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            copy(snippet)
                        } label: {
                            Label(
                                copiedID == snippet.id ? "已复制" : "复制",
                                systemImage: copiedID == snippet.id ? "checkmark" : "doc.on.doc"
                            )
                        }
                        .buttonStyle(.borderless)
                    }

                    ScrollView(.horizontal) {
                        Text(snippet.content)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func copy(_ snippet: Snippet) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet.content, forType: .string)
        copiedID = snippet.id
    }

    private func masked(_ key: String) -> String {
        guard key.count > 10 else { return "••••••••" }
        return "\(key.prefix(6))••••\(key.suffix(4))"
    }
}

private struct Snippet: Identifiable {
    let id: String
    let label: String
    let content: String
}
