import SwiftUI

@main
struct SummonApp: App {
    @State private var store = ConfigStore()

    var body: some Scene {
        MenuBarExtra("Summon", image: "MenuBarIcon") {
            MenuContent()
        }

        Window("About Summon", id: WindowID.about) {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Configure Shortcuts", id: WindowID.configure) {
            ConfigureView()
                .environment(store)
        }
        .defaultSize(width: 640, height: 420)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

enum WindowID {
    static let about = "about"
    static let configure = "configure"
}

private struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About Summon") { show(WindowID.about) }
        Button("Configure Shortcuts…") { show(WindowID.configure) }
        Divider()
        Button("Quit Summon") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Menu bar apps aren't active by default, and openWindow doesn't raise a
    /// window that's already open. So once the menu has closed (closing it
    /// can undo an earlier activation), activate the app and raise the window.
    private func show(_ id: String) {
        openWindow(id: id)
        DispatchQueue.main.async {
            NSApp.activate()
            // SwiftUI names scene windows "<scene id>-AppWindow-<n>".
            NSApp.windows
                .first { $0.identifier?.rawValue.hasPrefix(id) == true }?
                .makeKeyAndOrderFront(nil)
        }
    }
}
