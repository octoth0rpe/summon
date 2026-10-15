import AppKit
import TOMLKit

enum ConfigError: LocalizedError {
    case unknownModifier(String, in: String)

    var errorDescription: String? {
        switch self {
        case let .unknownModifier(token, keys):
            "Unknown modifier “\(token)” in “\(keys)”. Use cmd, shift, opt or ctrl."
        }
    }
}

/// Reads and writes config.toml.
///
///     [[shortcut]]
///     keys = "cmd+'"
///     app  = "com.apple.Safari"
enum ConfigFile {
    private struct File: Decodable {
        var shortcut: [Entry]?
    }

    private struct Entry: Decodable {
        var keys: String
        var app: String
    }

    static func parse(_ text: String) throws -> [Shortcut] {
        let file = try TOMLDecoder().decode(File.self, from: text)
        return try (file.shortcut ?? []).map { try Shortcut(keys: $0.keys, app: $0.app) }
    }

    /// Written by hand rather than with TOMLEncoder to keep the file
    /// readable: a header, `[[shortcut]]` tables, and app-name comments.
    @MainActor static func render(_ shortcuts: [Shortcut]) -> String {
        var out = """
            # Summon shortcuts. Summon reloads this file whenever it changes.
            #
            # keys: modifiers and a key joined with "+". Modifiers are cmd, shift,
            #       opt and ctrl. Keys are a single character (a, 1, ', /) or a name:
            #       space, return, tab, escape, delete, up, down, left, right,
            #       home, end, pageup, pagedown, f1–f20. Shifted characters
            #       work too: "cmd+|" means "cmd+shift+\" on a US layout.
            # app:  the bundle identifier of the app to launch. Find one with
            #       `osascript -e 'id of app "Safari"'`.
            #
            # [[shortcut]]
            # keys = "cmd+'"
            # app  = "com.apple.Safari"

            """
        for shortcut in shortcuts {
            out += "\n"
            if let name = appName(for: shortcut.app) {
                out += "# \(name)\n"
            }
            out += """
                [[shortcut]]
                keys = \(quote(shortcut.keys))
                app  = \(quote(shortcut.app))

                """
        }
        return out
    }

    @MainActor private static func appName(for bundleID: String) -> String? {
        guard !bundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return url.deletingPathExtension().lastPathComponent
    }

    /// A TOML basic string.
    private static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                out += String(format: "\\u%04X", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
