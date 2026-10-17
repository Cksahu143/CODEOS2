# CodeOS

A native macOS command center for development, written in SwiftUI and AppKit.
It brings your projects, files, apps, tools, system resources, and storage into
one window, and it can change your whole Mac's appearance on request.

## Requirements

- macOS 13 Ventura or later, Intel or Apple Silicon.
- Xcode Command Line Tools, or Xcode 14 or later.

```sh
xcode-select --install   # if the tools are not installed
```

## Build and run

```sh
swift test                  # unit tests for the logic layer
bash scripts/build-app.sh   # builds build/CodeOS.app (ad-hoc signed)
open build/CodeOS.app
```

You can also open `Package.swift` in Xcode and run the `CodeOS` scheme.
A locally built app is unsigned for distribution, so the first launch may need
right-click, then Open.

## Features

| Section | What it does |
|---|---|
| Home | Quick actions, your workspaces with an Open button, and a summary of this Mac. |
| Workspaces | A project folder with its editor, documentation links, and supporting apps. Open runs each step and reports every result. |
| Workflows | Reusable step lists. Steps: open folder, open folder in app, open link, launch app, open Terminal at a folder, check Git status, set macOS appearance, run a command. Commands use an explicit argument list and ask for confirmation before running. |
| Files | Browse, sort, filter, show hidden files. Open, Open With, Reveal in Finder, Open Terminal Here, rename, new folder, duplicate, move or copy to a folder, move to Trash. Nothing is overwritten. |
| Applications | Apps found in /Applications, /System/Applications, and ~/Applications. Search, favorites, launch, reveal. |
| Developer Tools | Detects git, swift, node, npm, and tsc on your PATH. Read-only Git status for a chosen repository. |
| Monitor | Live memory breakdown (used, app and system, compressed, inactive, free), the busiest processes by CPU and memory, and listening TCP ports with their owning process. Refresh interval is adjustable and can be paused. |
| Storage | Sizes of common developer caches (Xcode DerivedData, simulator caches, npm, Yarn, Homebrew, Gradle, Cargo). Scans a folder you choose for node_modules, .build, and build directories. Removal goes to the Trash after confirmation. |
| System | macOS version, model, processor, architecture, memory, and disk space. |
| Settings | Dark mode for the whole Mac, CodeOS's own window appearance, launch at login, show hidden files, configuration location. |

## Permissions

CodeOS asks only for what each feature needs.

- **Automation (System Events):** required once to change the macOS appearance.
  macOS shows the prompt the first time. If you deny it, enable CodeOS under
  System Settings > Privacy & Security > Automation.
- **Login Items:** required for Open at Login. macOS may ask you to approve the
  item in System Settings > General > Login Items.
- **No Full Disk Access and no administrator privileges.** CodeOS reads only the
  folders you browse, the folders your workflows name, and the caches listed in
  Storage.

## Privacy and safety

- Configuration is stored locally at `~/Library/Application Support/CodeOS/config.json`.
  Nothing is sent to any server, and there is no analytics or account.
- Commands run without a shell, so arguments are never interpreted as shell syntax.
- Destructive actions (moving files to the Trash) always ask first, and they are
  recoverable from the Trash.
- A corrupt configuration file is moved to a timestamped backup, not deleted.
- Monitor reads process and port information but cannot quit or kill processes.

## Distribution: signing and notarization

Distribution outside your own Mac needs an Apple Developer account, which costs
money and must be set up by you. Once it is set up:

```sh
export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="codeos-notary"
bash scripts/build-app.sh
bash scripts/notarize.sh
```

`Resources/Info.plist` contains a placeholder bundle identifier
(`com.example.codeos`). Replace it with your own before notarizing.

## Why CodeOS is not sandboxed

The App Sandbox would block several core features: launching arbitrary apps,
opening Terminal at any folder, running developer commands, reading arbitrary
project folders, and controlling System Events. CodeOS is therefore distributed
as a notarized, hardened-runtime app outside the Mac App Store. The App Store
requires a sandbox, so CodeOS cannot be listed there in its current form.

## Project layout

```
Sources/CodeOSCore/     Logic with no UI dependencies (unit tested):
                        models, persistence, validation, file planning,
                        Git parsing, process running, app and tool discovery,
                        workflow runner, process/memory/port monitoring,
                        storage advisor.
Sources/CodeOSApp/      SwiftUI and AppKit interface, native action executor,
                        system appearance, launch at login.
Tests/CodeOSCoreTests/  Unit tests for the core layer.
Resources/              Info.plist, hardened-runtime entitlements.
scripts/                build-app.sh and notarize.sh.
```

## Verification status

This code was written without access to a macOS machine or Swift toolchain.
**It has not been compiled or run.** Before relying on it:

1. `swift build` and fix any compile errors.
2. `swift test` and confirm the tests pass.
3. Launch the app and check each section. Test Dark mode, Launch at login,
   and moving a folder to the Trash on a copy of your data first.

## Known limits

- Monitor shows memory and CPU for each process but not per-app energy use.
- Listening ports are read with `lsof`, so processes owned by other users may
  appear without a name unless you run CodeOS with sufficient rights.
- The Storage advisor reports sizes of allocated blocks, which can differ from
  Finder's figures for cloud-synced or compressed files.
