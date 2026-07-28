import AppKit
import Foundation

@MainActor
final class NodeStore: ObservableObject {
    @Published private(set) var nodes: [ProxyNode] = []
    @Published private(set) var snapshots: [UUID: NodeSnapshot] = [:]
    @Published var selection: UUID?
    @Published var presentedEditor: NodeEditorMode?
    @Published var alertMessage: String?

    private let defaultsKey = "saved-proxy-nodes"
    private let apiClient = ManagementAPIClient()

    init() {
        load()
        selection = nodes.first?.id
        Task { await refreshAll() }
    }

    func snapshot(for node: ProxyNode) -> NodeSnapshot {
        snapshots[node.id] ?? .empty
    }

    func add(name: String, address: String, key: String) {
        let node = ProxyNode(name: name, address: address)
        do {
            try KeychainStore.save(key, for: node.id)
            nodes.append(node)
            selection = node.id
            save()
            Task { await refresh(node) }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func update(_ node: ProxyNode, name: String, address: String, key: String) {
        guard let index = nodes.firstIndex(where: { $0.id == node.id }) else { return }
        do {
            if !key.isEmpty {
                try KeychainStore.save(key, for: node.id)
            }
            nodes[index].name = name
            nodes[index].address = ProxyNode.normalize(address)
            save()
            Task { await refresh(nodes[index]) }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func remove(_ node: ProxyNode) {
        KeychainStore.delete(for: node.id)
        nodes.removeAll { $0.id == node.id }
        snapshots[node.id] = nil
        if selection == node.id { selection = nodes.first?.id }
        save()
    }

    func refresh(_ node: ProxyNode) async {
        snapshots[node.id] = NodeSnapshot(state: .checking)
        guard let key = KeychainStore.read(for: node.id), !key.isEmpty else {
            snapshots[node.id] = NodeSnapshot(
                state: .offline("尚未保存 Management Key"),
                lastChecked: Date()
            )
            return
        }
        snapshots[node.id] = await apiClient.fetchSnapshot(node: node, managementKey: key)
    }

    func refreshAll() async {
        await withTaskGroup(of: (UUID, NodeSnapshot).self) { group in
            for node in nodes {
                snapshots[node.id] = NodeSnapshot(state: .checking)
                guard let key = KeychainStore.read(for: node.id), !key.isEmpty else {
                    snapshots[node.id] = NodeSnapshot(
                        state: .offline("尚未保存 Management Key"),
                        lastChecked: Date()
                    )
                    continue
                }
                group.addTask { [apiClient] in
                    let snapshot = await apiClient.fetchSnapshot(node: node, managementKey: key)
                    return (node.id, snapshot)
                }
            }
            for await (id, snapshot) in group {
                snapshots[id] = snapshot
            }
        }
    }

    func openManagementPage(for node: ProxyNode) {
        guard let url = node.managementPageURL else { return }
        NSWorkspace.shared.open(url)
    }

    func key(for node: ProxyNode) -> String {
        KeychainStore.read(for: node.id) ?? ""
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let savedNodes = try? JSONDecoder().decode([ProxyNode].self, from: data)
        else {
            return
        }
        nodes = savedNodes
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(nodes) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

enum NodeEditorMode: Identifiable {
    case add
    case edit(ProxyNode)

    var id: String {
        switch self {
        case .add: "add"
        case let .edit(node): node.id.uuidString
        }
    }
}

