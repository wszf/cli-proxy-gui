import AppKit
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var instanceLock: SingleInstanceLock?

    func applicationWillFinishLaunching(_ notification: Notification) {
        let lock = SingleInstanceLock(identifier: Bundle.main.bundleIdentifier ?? "com.wszf.cli-proxy-gui")
        guard lock.acquire() else {
            activateExistingInstance()
            NSApp.terminate(nil)
            return
        }
        instanceLock = lock
    }

    func applicationWillTerminate(_ notification: Notification) {
        instanceLock = nil
    }

    private func activateExistingInstance() {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentProcessIdentifier }?
            .activate(options: [.activateAllWindows])
    }
}

final class SingleInstanceLock {
    private let lockURL: URL
    private var fileDescriptor: Int32 = -1

    init(identifier: String, directory: URL? = nil) {
        let baseDirectory = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        lockURL = baseDirectory
            .appending(path: identifier, directoryHint: .isDirectory)
            .appending(path: "instance.lock")
    }

    deinit {
        release()
    }

    func acquire() -> Bool {
        guard fileDescriptor == -1 else { return true }

        do {
            try FileManager.default.createDirectory(
                at: lockURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return false
        }

        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return false }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            return false
        }

        fileDescriptor = descriptor
        return true
    }

    private func release() {
        guard fileDescriptor >= 0 else { return }
        flock(fileDescriptor, LOCK_UN)
        Darwin.close(fileDescriptor)
        fileDescriptor = -1
    }
}
