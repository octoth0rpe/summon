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

    /// Menu bar apps aren't active by default, so bring the app forward
    /// or the window opens behind whatever the user is working in.
    private func show(_ id: String) {
        NSApp.activate()
        openWindow(id: id)
    }
}
