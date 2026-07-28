import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: NodeStore

    private var selectedNode: ProxyNode? {
        store.nodes.first { $0.id == store.selection }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let node = selectedNode {
                NodeDashboardView(node: node)
            } else {
                EmptyStateView()
            }
        }
        .sheet(item: $store.presentedEditor) { mode in
            NodeEditorView(mode: mode)
                .environmentObject(store)
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { store.alertMessage != nil },
                set: { if !$0 { store.alertMessage = nil } }
            )
        ) {
            Button("好") { store.alertMessage = nil }
        } message: {
            Text(store.alertMessage ?? "")
        }
    }

    private var sidebar: some View {
        List(selection: $store.selection) {
            Section("CLIProxyAPI 节点") {
                ForEach(store.nodes) { node in
                    NodeRowView(node: node, snapshot: store.snapshot(for: node))
                        .tag(node.id)
                        .contextMenu {
                            Button("编辑") { store.presentedEditor = .edit(node) }
                            Button("刷新") { Task { await store.refresh(node) } }
                            Divider()
                            Button("删除", role: .destructive) { store.remove(node) }
                        }
                }
            }
        }
        .overlay {
            if store.nodes.isEmpty {
                ContentUnavailableView(
                    "还没有节点",
                    systemImage: "server.rack",
                    description: Text("添加你的第一个 CLIProxyAPI 节点")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.presentedEditor = .add
                } label: {
                    Label("添加节点", systemImage: "plus")
                }

                Button {
                    Task { await store.refreshAll() }
                } label: {
                    Label("刷新全部", systemImage: "arrow.clockwise")
                }
                .disabled(store.nodes.isEmpty)
            }
        }
    }
}

private struct NodeRowView: View {
    let node: ProxyNode
    let snapshot: NodeSnapshot

    var body: some View {
        HStack(spacing: 10) {
            StatusIndicator(state: snapshot.state)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .fontWeight(.medium)
                Text(URL(string: node.address)?.host ?? node.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

struct StatusIndicator: View {
    let state: NodeConnectionState

    var body: some View {
        Group {
            if state == .checking {
                ProgressView().controlSize(.small)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
            }
        }
        .frame(width: 12, height: 12)
    }

    private var color: Color {
        switch state {
        case .online: .green
        case .offline: .red
        case .idle, .checking: .secondary
        }
    }
}

private struct EmptyStateView: View {
    @EnvironmentObject private var store: NodeStore

    var body: some View {
        ContentUnavailableView {
            Label("统一管理 CLIProxyAPI", systemImage: "server.rack")
        } description: {
            Text("节点地址保存在本机，Management Key 安全存入 macOS 钥匙串。")
        } actions: {
            Button("添加节点") { store.presentedEditor = .add }
                .buttonStyle(.borderedProminent)
        }
    }
}

