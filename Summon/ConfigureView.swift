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
                }
            }

            Divider()

            HStack {
                Button("Add Shortcut", systemImage: "plus") {
                    store.shortcuts.append(Shortcut())
                }
                Spacer()
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

            Picker("App", selection: $shortcut.app) {
                if shortcut.app.isEmpty {
                    Text("Choose an App…").tag("")
                } else if catalog.app(for: shortcut.app) == nil {
                    // Configured in the file but not in the scanned folders.
                    Text(shortcut.app).tag(shortcut.app)
                }
                ForEach(catalog.apps) { app in
                    Label {
                        Text(app.name)
                    } icon: {
                        Image(nsImage: catalog.icon(for: app))
                    }
                    .tag(app.bundleID)
                }
            }
            .labelsHidden()

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
