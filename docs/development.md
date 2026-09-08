# Development

Requires macOS 14+ and a Swift 5.9+ toolchain (Xcode command line tools). There is no Xcode
project — a Swift Package plus a Makefile that assembles the bundle.

```sh
git clone git@github.com:priyomukul/flare.git
cd flare
make run
```

`make run` builds the executable, assembles `dist/Flare.app` (with `LSUIElement` so there is
no Dock icon), ad-hoc signs it, and launches it. Look for the beacon in the menu bar.

| Target | What it does |
| --- | --- |
| `make build` | `swift build -c release` |
| `make app` | Assemble and ad-hoc sign `dist/Flare.app` |
| `make run` | `make app`, then relaunch |
| `make stop` | Quit a running Flare |
| `make install` | Copy the bundle to `/Applications` |
| `make debug` | The same bundle, built `-c debug` |
| `make icon` | Rebuild `Resources/Flare.icns` from the 1024pt PNG |
| `make dmg` | Build the drag-and-drop `dist/Flare-<version>.dmg` |
| `make release` | Cut a GitHub release and attach the DMG (needs `gh`) |
| `make smoke` | Run `scripts/smoke.sh` against a running Flare |
| `make clean` | Remove `.build` and `dist` |

Check it works:

```sh
curl -s -X POST http://127.0.0.1:4242/waiting -d '{"agent":"test"}'
```

Every screen should flash, and the menu bar should show `1` next to the beacon.

> If you have Flare installed from Homebrew *and* a build in `dist/`, only one of them can
> hold the port. Run `make stop` first, or quit the installed copy.

## Layout

```
Package.swift
Sources/Flare/
  App.swift            NSApplicationDelegate, status item, menu
  AgentStore.swift     Who is waiting, and for how long
  HTTPListener.swift   NWListener + a minimal HTTP/1.1 parser
  FlashOverlay.swift   One overlay window per screen, and the pulse animation
  Reminder.swift       Reminder timer and return-to-desk detection
  Pause.swift          Pause state
  Prefs.swift          UserDefaults
  SettingsView.swift   The one SwiftUI view, plus SMAppService and its window
  HooksSnippet.swift   The hooks JSON, with the live port
  UpdateChecker.swift  Daily GitHub release check; never installs anything
Resources/
  Info.plist           LSUIElement, bundle id, icon name
  Flare.icns           App icon, all ten sizes
  flare-icon-1024.png  Icon source; `make icon` regenerates the .icns from this
  flare-icon.svg       Vector original
Makefile               Build, bundle, sign, run
scripts/
  smoke.sh             Route-by-route check against a running Flare
  make-dmg.sh          Builds the drag-and-drop installer
  dmg-background.swift Renders the DMG window background at 1x and 2x
Casks/flare.rb         Homebrew cask
docs/                  You are here
```

## Testing

`make smoke` is the automated suite: 30 assertions across every route, both payload shapes,
duplicate directory names, six kinds of bad input, and a 20-call burst. It asserts on every
response body, so a broken server fails it rather than printing a green tick.

The nag loop is easy to watch without waiting two minutes:

```sh
defaults write com.priyomukul.flare reminderInterval -float 30
# leave one agent waiting, watch the screen for a minute
defaults delete com.priyomukul.flare reminderInterval
```

Three things need you at the keyboard, because they need real hardware events:

- **Full-screen coverage** — put an app in full screen, then `curl -X POST
  http://127.0.0.1:4242/waiting -d '{"agent":"test"}'` from a second terminal. The flash
  should land on top.
- **Display sleep and monitor plug/unplug** — leave an agent waiting, sleep the displays
  (`pmset displaysleepnow`) or unplug an external monitor, then come back. Flare should flash
  once on your return, with no leftover overlay showing on any screen.
- **Pause and Resume** — click through Pause ▸ 15 min, confirm nothing flashes while a signal
  arrives, then Resume and confirm it flashes at once.

Without Screen Recording permission you cannot screenshot the overlay, but you can still
verify it exists and is torn down correctly — `CGWindowListCopyWindowInfo` reports window
owner, level and bounds without any permission, and overlay windows show up at level 1000.

## Releasing

Before cutting anything: bump `CFBundleShortVersionString` and `CFBundleVersion` in
`Resources/Info.plist`, bump `version` in `Casks/flare.rb`, add the release's section to
[CHANGELOG.md](../CHANGELOG.md), and push — `gh` tags the remote default branch as it stands.

```sh
make release        # builds the DMG, cuts the tag, uploads, prints the sha256
```

Then update `sha256` in `Casks/flare.rb` with the hash of the asset downloaded back from
GitHub, not the value printed from the local build — the DMG is not byte-reproducible, so the
two differ and only the published one matters.
