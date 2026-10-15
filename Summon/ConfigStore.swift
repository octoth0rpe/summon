import AppKit
import Observation

/// Owns the shortcut list: loads it from config.toml, saves edits made in
/// the UI, reloads when the file changes on disk, and keeps the registered
/// hotkeys in sync.
@MainActor @Observable
final class ConfigStore {
    var shortcuts: [Shortcut] = [] {
        didSet {
            guard shortcuts != oldValue else { return }
            hotKeys.register(shortcuts.filter(\.isComplete)) { shortcut in
                Launcher.launch(shortcut.app)
            }
            if !isApplyingFile { save() }
        }
    }

    /// Set when config.toml can't be read or parsed. The last good shortcuts stay active.
    private(set) var loadError: String?

    let fileURL: URL

    @ObservationIgnored private let hotKeys = HotKeyManager()
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var isApplyingFile = false

    init() {
        // Inside the sandbox this resolves to
        // ~/Library/Containers/<bundle id>/Data/Library/Application Support.
        let dir = URL.applicationSupportDirectory.appending(path: "Summon", directoryHint: .isDirectory)
        fileURL = dir.appending(path: "config.toml")

        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: fileURL.path) {
            try? ConfigFile.render([]).write(to: fileURL, atomically: true, encoding: .utf8)
        }

        reload()
        watcher = FileWatcher(url: fileURL) { [weak self] in self?.reload() }
    }

    func reload() {
        do {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            let parsed = try ConfigFile.parse(text).map(\.normalized)
            loadError = nil
            // Our own saves come back through the watcher; this skips them.
            guard parsed != shortcuts else { return }
            isApplyingFile = true
            shortcuts = parsed
            isApplyingFile = false
        } catch {
            loadError = String(describing: error)
        }
    }

    private func save() {
        do {
            try ConfigFile.render(shortcuts).write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            loadError = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
