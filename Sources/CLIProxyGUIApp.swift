import SwiftUI

@main
struct CLIProxyGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = NodeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 580)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(after: .newItem) {
                Button("刷新所有节点") {
                    Task { await store.refreshAll() }
                }
                .keyboardShortcut("r")
            }
        }
    }
}
