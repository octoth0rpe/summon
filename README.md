# Summon

A tiny macOS menu bar app that launches (or focuses) apps with global keyboard shortcuts.
Press `⌘'`, get Safari. Shortcuts live in a TOML file that Summon watches and hot-reloads,
so you can edit them in the built-in Configure window or in your editor of choice.

- Native SwiftUI, macOS 26 (Tahoe) and later
- Menu bar only, no Dock icon
- App Sandbox enabled; no Accessibility or Input Monitoring permission needed
- One dependency: [TOMLKit](https://github.com/LebJe/TOMLKit)

## Quick start

Requirements: Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make run        # generate the project, build Debug, launch
```

Or open it in Xcode:

```sh
make project    # writes Summon.xcodeproj from project.yml
open Summon.xcodeproj
```

The Makefile points `DEVELOPER_DIR` at `/Applications/Xcode.app`, so it works even if
`xcode-select` still points at the Command Line Tools. Override with
`make DEVELOPER_DIR=/path/to/Xcode-beta.app/Contents/Developer`.

| Target         | What it does                                     |
|----------------|--------------------------------------------------|
| `make project` | Regenerate `Summon.xcodeproj` from `project.yml`  |
| `make build`   | Debug build into `build/`                        |
| `make run`     | Build, quit any running Summon, launch the new one |
| `make clean`   | Remove `build/` and the generated project        |

## Configuration

Summon is sandboxed, so its config lives in its container:

```
~/Library/Containers/com.octoth0rpe.summon/Data/Library/Application Support/Summon/config.toml
```

**Configure Shortcuts… → Show Config File** reveals it in Finder. The file is created
on first launch with a commented header.

```toml
# Safari
[[shortcut]]
keys = "cmd+'"
app  = "com.apple.Safari"

# Terminal
[[shortcut]]
keys = "ctrl+opt+t"
app  = "com.apple.Terminal"
```

- **`keys`**: modifiers and one key joined with `+`.
  - Modifiers: `cmd`, `shift`, `opt`, `ctrl`. The aliases `command`, `option`, `alt`,
    `control` and the symbols `⌘⇧⌥⌃` also work.
  - Key: a single character (`a`, `1`, `'`, `/`) or a name: `space`, `return`, `tab`,
    `escape`, `delete`, `forwarddelete`, `up`, `down`, `left`, `right`, `home`, `end`,
    `pageup`, `pagedown`, `f1`–`f20`. Use `cmd++` for the plus key.
  - Characters are matched against your current keyboard layout, so `'` means the key
    that types `'` on your layout, not a fixed physical key.
  - Characters typed with Shift become Shift plus the base key: on a US layout `cmd+|`
    means `cmd+shift+\` and `cmd++` means `cmd+shift+=`. The Configure window rewrites
    them as you type. Letters are case-insensitive, so `cmd+K` is just `cmd+k`.
  - Keypad keys aren't supported; `1` and `+` always mean the main-keyboard keys.
- **`app`**: the app's bundle identifier. Find one with
  `osascript -e 'id of app "Safari"'`.

Pressing a shortcut launches the app, or brings it to the front if it's already running.

Edits from either side show up on the other. Saving the file reloads shortcuts
immediately. Edits in the Configure window rewrite the file, which means comments
and formatting you added by hand are replaced with the generated layout. If the file
has a syntax error, Summon keeps the last working shortcuts and shows the parse error
in the Configure window.

## Architecture

```
Summon/
├── SummonApp.swift      App entry: MenuBarExtra + About and Configure windows
├── ConfigStore.swift    Source of truth: load, save, reload, keep hotkeys in sync
├── ConfigFile.swift     TOML parse (TOMLKit) and render (hand-written for readability)
├── Shortcut.swift       Shortcut and Modifier models, "cmd+shift+k" parsing
├── HotKeyManager.swift  Global hotkeys via Carbon RegisterEventHotKey
├── KeyCodes.swift       Key name → virtual key code, layout-aware via UCKeyTranslate
├── FileWatcher.swift    kqueue (DispatchSource) watcher for config.toml
├── Launcher.swift       NSWorkspace.openApplication
├── AppCatalog.swift     Scans the Applications folders for the app picker
├── ConfigureView.swift  Shortcut editor, launch-at-login toggle
├── AboutView.swift
└── Assets.xcassets      App icon PNGs and the menu bar template SVG
```

How a change flows:

```
UI edit ──► ConfigStore.shortcuts ──► didSet ──► HotKeyManager.register
                    ▲                        └──► save() ──► config.toml
                    │                                             │
               reload() ◄── FileWatcher ◄─────────────────────────┘
```

`ConfigStore.reload()` compares the parsed shortcuts with the ones in memory, ignoring
row IDs, and does nothing when they match. That's how our own saves round-trip through
the watcher without resetting rows in the UI while you type.

### Design decisions

- **Carbon hotkeys, not an event tap.** `RegisterEventHotKey` is old but it's still what
  shipping hotkey apps use. It works in the sandbox and needs no TCC permission. A
  `CGEventTap` would need Accessibility or Input Monitoring permission, which hurts both
  setup and App Review. The cost is that a combo can be refused if another app already
  registered it; Summon skips those silently for now.
- **Bundle IDs, not app names.** IDs are stable across renames, localizations and
  duplicate names. The UI and the comments in the generated file show the names.
- **Watching the directory and the file.** Many editors (vim, VS Code, anything doing
  "atomic save") write a temp file and rename it over the original. A watch on the
  original file then points at a deleted inode. The directory watch catches that, and
  the file watch is re-attached on every event. kqueue events are push-based, so idle
  cost is zero. Events are debounced by 150 ms.
- **Sandbox from day one.** This keeps the App Store an option. The main cost is the
  config path above. The app scanner reads the real `~/Applications` via `getpwuid`;
  if the sandbox ever blocks that, those apps just don't appear in the picker, though
  they still work when written into the file by hand.
- **Swift 6 language mode.** Everything stateful is `@MainActor`. Carbon and
  DispatchSource callbacks arrive on the main thread and hop in with
  `MainActor.assumeIsolated`.

## Icons

The source artwork is in [`icons/`](icons/) (see [`icons/ICONS.md`](icons/ICONS.md)).
`Assets.xcassets/AppIcon.appiconset` holds PNGs rendered from `app-icon-light.svg`. The
menu bar icon is `menubar-template.svg`, set to render as a template image.

TODO: build a `.icon` in Icon Composer from the layered SVGs to get the dark, tinted and
Liquid Glass variants. Then drop the `.icon` into the target and remove the appiconset.

## Distribution notes

- Debug builds are ad-hoc signed (`CODE_SIGN_IDENTITY: "-"` in `project.yml`), so no
  developer account is needed to build and run locally.
- For the App Store or notarized builds: set `DEVELOPMENT_TEAM`, remove the ad-hoc
  identity, and change `PRODUCT_BUNDLE_IDENTIFIER` if needed. The sandbox entitlement
  and hardened runtime are already on.
- Launch at login uses `SMAppService.mainApp`. It's most reliable when the app lives in
  `/Applications`. A build launched from `build/` can register itself, but the login
  item then points at that build.

## Ideas / not yet done

- Toggle behavior: pressing the shortcut for the frontmost app hides it
- A "record shortcut" field that captures the next key press
- Warnings for duplicate shortcuts or combos macOS refuses
- An "Other…" app picker (NSOpenPanel) for apps outside the scanned folders

## License

See [LICENSE](LICENSE).
