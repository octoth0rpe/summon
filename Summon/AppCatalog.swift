import AppKit
import Observation

struct AppInfo: Identifiable, Hashable, Sendable {
    let bundleID: String
    let name: String
    let url: URL
    var id: String { bundleID }
}

/// A folder the user granted access to. The sandbox keeps Summon out of
/// the home directory, including ~/Applications, unless the user picks the
/// folder in an open panel; the bookmark keeps that grant across launches.
struct AppFolder: Identifiable {
    let url: URL
    let bookmark: Data
    var id: URL { url }

    var displayPath: String {
        let home = AppCatalog.realHome
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

/// The installed apps offered in the Configure window's app picker.
@MainActor @Observable
final class AppCatalog {
    private(set) var apps: [AppInfo] = []
    /// `apps` as menu items, built once per scan. Each row's pop-up shows a copy.
    private(set) var menu = NSMenu()
    private(set) var folders: [AppFolder] = []
    /// ~/Applications exists but the sandbox won't let us read it, and the
    /// user hasn't granted it (or dismissed the prompt to).
    private(set) var needsHomeApplicationsAccess = false
    @ObservationIgnored private var icons: [String: NSImage] = [:]

    private static let systemRoots = ["/Applications", "/System/Applications"]
    private static let bookmarksKey = "appFolderBookmarks"
    private static let dismissedPromptKey = "dismissedHomeApplicationsPrompt"
    private static var homeApplications: URL {
        URL(filePath: realHome).appending(path: "Applications", directoryHint: .isDirectory)
    }

    /// The sandbox remaps NSHomeDirectory() to the app's container; this is the real one.
    nonisolated static let realHome =
        getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()

    init() {
        let bookmarks = UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data] ?? []
        folders = bookmarks.compactMap(Self.resolve)
        saveBookmarks() // Persists any bookmarks refreshed because they were stale.
    }

    func refresh() async {
        let roots = Self.systemRoots.map { URL(filePath: $0, directoryHint: .isDirectory) } + folders.map(\.url)
        apps = await Task.detached(priority: .userInitiated) { Self.scan(roots) }.value
        menu = NSMenu()
        for app in apps {
            let item = NSMenuItem(title: app.name, action: nil, keyEquivalent: "")
            item.image = icon(for: app)
            item.representedObject = app.bundleID
            menu.addItem(item)
        }
        needsHomeApplicationsAccess = !UserDefaults.standard.bool(forKey: Self.dismissedPromptKey)
            && Self.isBlocked(Self.homeApplications)
    }

    func dismissHomeApplicationsPrompt() {
        UserDefaults.standard.set(true, forKey: Self.dismissedPromptKey)
        needsHomeApplicationsAccess = false
    }

    /// True when the folder exists but the sandbox denies reading it. A missing
    /// folder reports "not found" instead, so there's nothing to ask for.
    private static func isBlocked(_ url: URL) -> Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            return false
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            return true
        } catch {
            return false
        }
    }

    /// A 16 pt copy of the app's icon, sized for menus.
    func icon(for app: AppInfo) -> NSImage {
        if let icon = icons[app.bundleID] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: app.url.path).copy() as! NSImage
        icon.size = NSSize(width: 16, height: 16)
        icons[app.bundleID] = icon
        return icon
    }

    // MARK: Granted folders

    /// Shows an open panel in the home folder, where Applications is one click away.
    func addFolders() async {
        let panel = NSOpenPanel()
        let validator = NotHomeValidator()
        panel.delegate = validator
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(filePath: Self.realHome, directoryHint: .isDirectory)
        panel.prompt = "Add"
        panel.message = "Select the Applications folder (or any other folder with apps in it) and click Add."
        guard panel.runModal() == .OK else { return }

        for url in panel.urls where !folders.contains(where: { $0.url == url }) {
            // Access from the panel lasts until quit; the bookmark is what lasts beyond that.
            guard let bookmark = try? url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil, relativeTo: nil)
            else { continue }
            folders.append(AppFolder(url: url, bookmark: bookmark))
        }
        saveBookmarks()
        await refresh()
    }

    func remove(_ folder: AppFolder) async {
        folder.url.stopAccessingSecurityScopedResource()
        folders.removeAll { $0.id == folder.id }
        saveBookmarks()
        await refresh()
    }

    private func saveBookmarks() {
        UserDefaults.standard.set(folders.map(\.bookmark), forKey: Self.bookmarksKey)
    }

    /// Resolves a saved bookmark and starts accessing it for the rest of the run,
    /// since icons are loaded lazily from these folders.
    private static func resolve(_ bookmark: Data) -> AppFolder? {
        var isStale = false
        guard let url = try? URL(
                resolvingBookmarkData: bookmark, options: .withSecurityScope,
                relativeTo: nil, bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource()
        else { return nil }
        guard isStale else { return AppFolder(url: url, bookmark: bookmark) }
        let fresh = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil)
        return AppFolder(url: url, bookmark: fresh ?? bookmark)
    }

    /// Clicking Add with nothing selected would choose the folder being shown,
    /// the home folder, and grant read access to all of it. Refuse that.
    private final class NotHomeValidator: NSObject, NSOpenSavePanelDelegate {
        func panel(_ sender: Any, validate url: URL) throws {
            guard url.standardizedFileURL.path == AppCatalog.realHome else { return }
            throw NSError(domain: "Summon", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Select a folder inside your home folder, such as Applications.",
            ])
        }
    }

    // MARK: Scanning

    nonisolated private static func scan(_ roots: [URL]) -> [AppInfo] {
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

        for root in roots { visit(root, depth: 1) }
        add(URL(filePath: "/System/Library/CoreServices/Finder.app"))

        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
