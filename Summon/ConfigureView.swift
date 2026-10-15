import ServiceManagement
import SwiftUI

struct ConfigureView: View {
    @Environment(ConfigStore.self) private var store
    @State private var catalog = AppCatalog()

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            if let error = store.loadError {
                ErrorBanner(message: error)
            }
            if catalog.needsHomeApplicationsAccess {
                HomeApplicationsBanner(catalog: catalog)
            }

            if store.shortcuts.isEmpty {
                ContentUnavailableView(
                    "No Shortcuts", systemImage: "keyboard",
                    description: Text("Click Add Shortcut to summon your first app."))
            } else {
                List {
                    ForEach($store.shortcuts) { $shortcut in
                        ShortcutRow(shortcut: $shortcut, catalog: catalog) {
                            store.shortcuts.removeAll { $0.id == shortcut.id }
                        }
                    }
                    .onDelete { store.shortcuts.remove(atOffsets: $0) }
                    .onMove { store.shortcuts.move(fromOffsets: $0, toOffset: $1) }
                }
            }

            Divider()

            HStack {
                Button("Add Shortcut", systemImage: "plus") {
                    store.shortcuts.append(Shortcut())
                }
                Spacer()
                AppFoldersMenu(catalog: catalog)
                LaunchAtLoginToggle()
                Button("Show Config File") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                }
            }
            .padding(12)
        }
        .frame(minWidth: 600, minHeight: 260)
        .task { await catalog.refresh() }
    }
}

private struct ShortcutRow: View {
    @Binding var shortcut: Shortcut
    let catalog: AppCatalog
    let onDelete: () -> Void

    private var keyIsInvalid: Bool {
        !shortcut.key.isEmpty && KeyCodes.code(for: shortcut.key) == nil
    }

    var body: some View {
        HStack(spacing: 6) {
            // Rows drag from anywhere that isn't a control; the grip just shows that.
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")

            ForEach(Modifier.allCases, id: \.self) { modifier in
                Toggle(modifier.symbol, isOn: binding(for: modifier))
                    .toggleStyle(.button)
                    .help(modifier.name)
            }

            TextField("Key", text: $shortcut.key)
                .onChange(of: shortcut.key) { shortcut = shortcut.normalized }
                .frame(width: 72)
                .multilineTextAlignment(.center)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(.red, lineWidth: 1)
                        .opacity(keyIsInvalid ? 1 : 0)
                }
                .help(keyIsInvalid
                      ? "Unknown key. Use a single character or a name like space, return, up or f5."
                      : "A single character, or a name like space, return, up or f5")

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            AppPicker(selection: $shortcut.app, catalog: catalog)
                // Fill the row, so every pop-up is the same width whatever it shows.
                .frame(maxWidth: .infinity)

            Button("Delete", systemImage: "minus.circle", action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Delete this shortcut")
        }
        .padding(.vertical, 2)
    }

    private func binding(for modifier: Modifier) -> Binding<Bool> {
        Binding {
            shortcut.modifiers.contains(modifier)
        } set: { isOn in
            if isOn { shortcut.modifiers.insert(modifier) } else { shortcut.modifiers.remove(modifier) }
        }
    }
}

/// The app pop-up: an NSPopUpButton that holds only the chosen app until it
/// opens, then shows a copy of the catalog's menu.
///
/// A SwiftUI Picker resolves all ~170 items through the view graph every time
/// a row is built, edited, or re-hosted by the List as it scrolls: about 100 ms
/// a row, which made the window slow to open and hitch while scrolling. Even an
/// NSPopUpButton that always carries the full menu costs ~25 ms a row in layout,
/// so the list is filled on NSPopUpButton.willPopUpNotification instead.
private struct AppPicker: NSViewRepresentable {
    @Binding var selection: String
    let catalog: AppCatalog

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PopUpButton {
        let button = PopUpButton()
        button.target = context.coordinator
        button.action = #selector(Coordinator.choose(_:))
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.willPopUp(_:)),
            name: NSPopUpButton.willPopUpNotification, object: button)
        return button
    }

    func updateNSView(_ button: PopUpButton, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.source = catalog.menu
        let menu = NSMenu()
        menu.addItem(Self.item(for: selection, in: catalog.menu))
        button.menu = menu
        button.selectItem(at: 0)
    }

    /// A copy of the catalog's item for the app, or a stand-in when nothing is
    /// chosen yet or the app isn't in the scanned folders.
    static func item(for bundleID: String, in source: NSMenu) -> NSMenuItem {
        let index = source.indexOfItem(withRepresentedObject: bundleID)
        if index >= 0, let item = source.item(at: index)?.copy() as? NSMenuItem { return item }
        let item = NSMenuItem(title: bundleID.isEmpty ? "Choose an App…" : bundleID,
                              action: nil, keyEquivalent: "")
        item.representedObject = bundleID
        return item
    }

    /// An NSPopUpButton's natural width is its widest item. The row sets the
    /// width instead, so every row's pop-up is the same size.
    final class PopUpButton: NSPopUpButton {
        @MainActor private static let height = NSPopUpButton().intrinsicContentSize.height

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<String>?
        var source: NSMenu?

        /// Swaps in the full list just before the menu opens. The next update
        /// trims it back to the chosen app.
        @objc func willPopUp(_ notification: Notification) {
            guard let button = notification.object as? NSPopUpButton, let source,
                  let menu = source.copy() as? NSMenu
            else { return }
            let selection = selection?.wrappedValue ?? ""
            var index = menu.indexOfItem(withRepresentedObject: selection)
            if index < 0 {
                menu.insertItem(AppPicker.item(for: selection, in: source), at: 0)
                index = 0
            }
            button.menu = menu
            button.selectItem(at: index)
        }

        @objc func choose(_ button: NSPopUpButton) {
            selection?.wrappedValue = button.selectedItem?.representedObject as? String ?? ""
        }
    }
}

/// Adds and removes folders, beyond /Applications, that the app picker lists.
private struct AppFoldersMenu: View {
    let catalog: AppCatalog

    var body: some View {
        Menu("App Folders") {
            Button("Add Folder…") {
                Task { await catalog.addFolders() }
            }
            if !catalog.folders.isEmpty {
                Divider()
                ForEach(catalog.folders) { folder in
                    Menu(folder.displayPath) {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([folder.url])
                        }
                        Button("Remove") {
                            Task { await catalog.remove(folder) }
                        }
                    }
                }
            }
        }
        .fixedSize()
        .help("Folders besides /Applications to look for apps in, such as ~/Applications")
    }
}

private struct HomeApplicationsBanner: View {
    let catalog: AppCatalog

    var body: some View {
        HStack {
            Image(systemName: "folder.badge.questionmark")
                .foregroundStyle(.blue)
            Text("Summon needs your permission to list the apps in ~/Applications.")
            Spacer()
            Button("Grant Access…") {
                Task { await catalog.addFolders() }
            }
            Button("Not Now", systemImage: "xmark") {
                catalog.dismissHomeApplicationsPrompt()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Don't ask again. You can still add it under App Folders.")
        }
        .font(.callout)
        .padding(10)
        .background(.blue.opacity(0.1))
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("config.toml has a problem, so Summon is still using the last working shortcuts.")
                    .bold()
                Text(message)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .font(.callout)
        .padding(10)
        .background(.yellow.opacity(0.12))
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var isEnabled = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        Toggle("Launch at login", isOn: Binding {
            isEnabled
        } set: { enable in
            do {
                if enable {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                self.error = error.localizedDescription
            }
            isEnabled = SMAppService.mainApp.status == .enabled
        })
        .onAppear { isEnabled = SMAppService.mainApp.status == .enabled }
        .alert("Couldn't change login item", isPresented: Binding {
            error != nil
        } set: { if !$0 { error = nil } }) {
            Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }
}
