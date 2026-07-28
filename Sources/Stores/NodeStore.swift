import AppKit
import Foundation

@MainActor
final class NodeStore: ObservableObject {
    @Published private(set) var nodes: [ProxyNode] = []
    @Published private(set) var snapshots: [UUID: NodeSnapshot] = [:]
    @Published private(set) var credentialQuotas: [UUID: [CredentialQuotaSummary]] = [:]
    @Published private(set) var credentialQuotaStates: [UUID: CredentialQuotaLoadState] = [:]
    @Published var selection: UUID?
    @Published var presentedEditor: NodeEditorMode?
    @Published var alertMessage: String?

    private static let credentialQuotaRefreshInterval: TimeInterval = 3 * 60
    private let defaultsKey = "saved-proxy-nodes"
    private let apiClient = ManagementAPIClient()
    private var credentialQuotaRefreshedAt: [UUID: Date] = [:]
    private var credentialQuotaRevisions: [UUID: Int] = [:]
    private var credentialQuotaRefreshTask: Task<Void, Never>?

    init() {
        load()
        selection = nodes.first?.id
        credentialQuotaRefreshTask = Task { [weak self] in
            await self?.refreshAll()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        for: .seconds(Self.credentialQuotaRefreshInterval)
                    )
                } catch {
                    return
                }
                guard let self else { return }
                await self.refreshCredentialQuotasForOnlineNodes()
            }
        }
    }

    deinit {
        credentialQuotaRefreshTask?.cancel()
    }

    func snapshot(for node: ProxyNode) -> NodeSnapshot {
        snapshots[node.id] ?? .empty
    }

    func quotas(for node: ProxyNode) -> [CredentialQuotaSummary] {
        credentialQuotas[node.id] ?? []
    }

    func quotaState(for node: ProxyNode) -> CredentialQuotaLoadState {
        credentialQuotaStates[node.id] ?? .idle
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
            invalidateCredentialQuotas(for: nodes[index])
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
        credentialQuotas[node.id] = nil
        credentialQuotaStates[node.id] = nil
        credentialQuotaRefreshedAt[node.id] = nil
        credentialQuotaRevisions[node.id] = nil
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
        let snapshot = await apiClient.fetchSnapshot(node: node, managementKey: key)
        snapshots[node.id] = snapshot
        if snapshot.state == .online {
            await refreshCredentialQuotas(node, managementKey: key)
        } else {
            credentialQuotas[node.id] = []
            credentialQuotaStates[node.id] = .idle
            credentialQuotaRefreshedAt[node.id] = nil
        }
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

        await refreshCredentialQuotasForOnlineNodes()
    }

    func openManagementPage(for node: ProxyNode) {
        guard let url = node.managementPageURL else { return }
        NSWorkspace.shared.open(url)
    }

    func key(for node: ProxyNode) -> String {
        KeychainStore.read(for: node.id) ?? ""
    }

    func invalidateCredentialQuotas(for node: ProxyNode) {
        credentialQuotaRefreshedAt[node.id] = nil
        credentialQuotaRevisions[node.id, default: 0] += 1
        credentialQuotaStates[node.id] = .idle
    }

    private func refreshCredentialQuotas(_ node: ProxyNode, managementKey: String) async {
        guard beginCredentialQuotaRefresh(for: node.id) else { return }
        let revision = credentialQuotaRevisions[node.id, default: 0]
        let quotas = (
            try? await apiClient.fetchCredentialQuotas(
                node: node,
                managementKey: managementKey
            )
        ) ?? []
        guard credentialQuotaRevisions[node.id, default: 0] == revision else { return }
        credentialQuotas[node.id] = quotas
        credentialQuotaStates[node.id] = .loaded
    }

    private func refreshCredentialQuotasForOnlineNodes() async {
        await withTaskGroup(of: (UUID, Int, [CredentialQuotaSummary]?).self) { group in
            for node in nodes where snapshots[node.id]?.state == .online {
                guard let key = KeychainStore.read(for: node.id),
                      !key.isEmpty,
                      beginCredentialQuotaRefresh(for: node.id)
                else {
                    continue
                }
                let revision = credentialQuotaRevisions[node.id, default: 0]
                group.addTask { [apiClient] in
                    let quotas = try? await apiClient.fetchCredentialQuotas(
                        node: node,
                        managementKey: key
                    )
                    return (node.id, revision, quotas)
                }
            }
            for await (id, revision, quotas) in group
                where credentialQuotaRevisions[id, default: 0] == revision
            {
                credentialQuotas[id] = quotas ?? []
                credentialQuotaStates[id] = .loaded
            }
        }
    }

    private func beginCredentialQuotaRefresh(for nodeID: UUID, now: Date = Date()) -> Bool {
        guard credentialQuotaStates[nodeID] != .loading else { return false }
        if let refreshedAt = credentialQuotaRefreshedAt[nodeID],
           now.timeIntervalSince(refreshedAt) < Self.credentialQuotaRefreshInterval {
            return false
        }
        credentialQuotaStates[nodeID] = .loading
        credentialQuotaRefreshedAt[nodeID] = now
        return true
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
