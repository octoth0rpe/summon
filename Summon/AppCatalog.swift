import AppKit
import Observation

struct AppInfo: Identifiable, Hashable, Sendable {
    let bundleID: String
    let name: String
    let url: URL
    var id: String { bundleID }
}

/// The installed apps offered in the Configure window's app picker.
@MainActor @Observable
final class AppCatalog {
    private(set) var apps: [AppInfo] = []
    @ObservationIgnored private var icons: [String: NSImage] = [:]

    func refresh() async {
        apps = await Task.detached(priority: .userInitiated) { Self.scan() }.value
    }

    func app(for bundleID: String) -> AppInfo? {
        apps.first { $0.bundleID == bundleID }
    }

    /// A 16 pt copy of the app's icon, sized for menus.
    func icon(for app: AppInfo) -> NSImage {
        if let icon = icons[app.bundleID] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: app.url.path).copy() as! NSImage
        icon.size = NSSize(width: 16, height: 16)
        icons[app.bundleID] = icon
        return icon
    }

    nonisolated private static func scan() -> [AppInfo] {
        // The sandbox remaps NSHomeDirectory() to the app's container; we want the real one.
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        let roots = ["/Applications", "/System/Applications", "\(home)/Applications"]
        let fm = FileManager.default
        var found: [String: AppInfo] = [:]

        func add(_ url: URL) {
            guard let id = Bundle(url: url)?.bundleIdentifier, found[id] == nil else { return }
            found[id] = AppInfo(bundleID: id, name: url.deletingPathExtension().lastPathComponent, url: url)
        }

        // Apps at the top level, plus one level of folders such as Utilities.
        func visit(_ dir: URL, depth: Int) {
            // Not .skipsHiddenFiles: /Applications/Safari.app is a symlink into a
            // system cryptex that carries the "hidden" flag, though Finder shows it.
            let items = (try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for item in items where !item.lastPathComponent.hasPrefix(".") {
                if item.pathExtension == "app" {
                    add(item)
                } else if depth > 0, (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    visit(item, depth: depth - 1)
                }
            }
        }

        for root in roots { visit(URL(filePath: root, directoryHint: .isDirectory), depth: 1) }
        add(URL(filePath: "/System/Library/CoreServices/Finder.app"))

        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
