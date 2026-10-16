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
make            # generate the project and build Debug
make install    # build Release, replace ~/Applications/Summon.app, relaunch
```

Or open it in Xcode:

```sh
make project    # writes Summon.xcodeproj from project.yml
open Summon.xcodeproj
```

The Makefile points `DEVELOPER_DIR` at `/Applications/Xcode.app`, so it works even if
`xcode-select` still points at the Command Line Tools. Override with
`make DEVELOPER_DIR=/path/to/Xcode-beta.app/Contents/Developer`.

| Target          | What it does                                                         |
|-----------------|----------------------------------------------------------------------|
| `make`          | Same as `make build`                                                  |
| `make build`    | Debug build into `build/`                                             |
| `make install`  | Release build; quit Summon, replace `~/Applications/Summon.app`, relaunch |
| `make run`      | Debug build; quit Summon, launch it from `build/`                     |
| `make release`  | Release build into `build/`                                           |
| `make project`  | Regenerate `Summon.xcodeproj` from `project.yml`                      |
| `make clean`    | Remove `build/` and the generated project                             |

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
    means `cmd+shift+\` and `cmd++` means `cmd+shift+=`. Summon rewrites them that way
    when it loads the file. Letters are case-insensitive, so `cmd+K` is just `cmd+k`.
  - Keypad keys aren't supported; `1` and `+` always mean the main-keyboard keys.
- **`app`**: the app's bundle identifier. Find one with
  `osascript -e 'id of app "Safari"'`.

Pressing a shortcut launches the app, or brings it to the front if it's already running.

In the Configure window, click a row's key button and press a key to record it. Hold
modifiers while you press it to set the toggles too (`⌘'` records `'` with ⌘); a bare
key leaves the toggles alone. Esc cancels. Summon's own shortcuts are paused while
recording, so you can record combos it already uses. Keypad keys and Escape can't be
recorded, and keys your keyboard lacks (F13–F20 on a laptop) can still be typed into the file.

A ⚠️ on a row means its shortcut may not work. Hover for the reason:
- **Same keys as a row above.** macOS registers a combo once per app, so the first
  row wins and this one is off.
- **macOS also uses these keys** (System Settings → Keyboard → Keyboard Shortcuts:
  Mission Control, Spaces, screenshots…). macOS's shortcut usually wins. The row stays
  registered, so it starts working if you turn the macOS one off. This check can't see
  every system shortcut (Spotlight's `⌘Space` isn't listed) or other apps' shortcuts:
  macOS doesn't report those, and registering a taken combo doesn't fail.
- **macOS refused these keys.** Rare, for the same reason.

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
├── AppCatalog.swift     Scans app folders for the app picker; user-granted folders
├── ConfigureView.swift  Shortcut editor, key recorder, launch-at-login toggle
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
  config path above. The other is that the sandbox blocks reading the home directory,
  including `~/Applications`. The app picker lists `/Applications` and
  `/System/Applications` on its own; other folders are added under **App Folders** in
  the Configure window. Each one is chosen in an open panel (the
  `user-selected.read-only` entitlement) and saved as a security-scoped bookmark in
  UserDefaults (`bookmarks.app-scope`), so access survives relaunches. When
  `~/Applications` exists but can't be read (permission denied, as opposed to not
  found), the Configure window shows a banner offering to grant it. Launching
  doesn't need any of this: LaunchServices finds apps by bundle ID anywhere, so a
  shortcut written into the file by hand works even if its app isn't in the picker.
- **Swift 6 language mode.** Everything stateful is `@MainActor`. Carbon and
  DispatchSource callbacks arrive on the main thread and hop in with
  `MainActor.assumeIsolated`.

## Icons

The source artwork is in [`icons/`](icons/) (see [`icons/ICONS.md`](icons/ICONS.md)).
`Assets.xcassets/AppIcon.appiconset` holds PNGs rendered from `app-icon-light.svg`. The
menu bar icon is `menubar-template.svg`, set to render as a template image.

TODO ([steps](icons/ICON-COMPOSER.md)): build a `.icon` in Icon Composer from the layered SVGs to get the dark, tinted and
Liquid Glass variants. Then drop the `.icon` into the target and remove the appiconset.

## Distribution notes

- Debug builds are ad-hoc signed (`CODE_SIGN_IDENTITY: "-"` in `project.yml`), so no
  developer account is needed to build and run locally.
- For the App Store or notarized builds: set `DEVELOPMENT_TEAM`, remove the ad-hoc
  identity, and change `PRODUCT_BUNDLE_IDENTIFIER` if needed. The sandbox entitlement
  and hardened runtime are already on.
- Launch at login uses `SMAppService.mainApp`, which registers the copy of the app that
  turned it on. Turn it on from the `make install` copy in `~/Applications`, not from a
  `make run` build in `build/`.

## Ideas / not yet done

- Toggle behavior: pressing the shortcut for the frontmost app hides it
- An "Other…" item in the app picker for a single app outside the app folders
- Per-shortcut conditions: this Mac only, a time window, not when an app is in front


## License

See [LICENSE](LICENSE).
