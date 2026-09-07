# Design notes

Why Flare is built the way it is, including the places where an obvious approach turned out to
be wrong. Read this before changing the corresponding code.

## The app

- **`agent` wins over `session_id`** if a body somehow contains both — a caller that names
  itself explicitly meant it.
- **Duplicate names** get the first four characters of the session id in parentheses:
  `api-server (3f2b)`. A simple payload keeps its bare name even in a collision, since its id
  *is* its name and `web (web)` would say nothing.
- **`since` survives a refresh.** Repeated `Stop` hooks for one session keep showing how long
  that session has actually been waiting, not how long since the last hook.
- **An expired timed pause behaves like Resume** — it flashes immediately if something is
  waiting, which is the point of pausing for fifteen minutes.
- **`Content-Length` only.** The parser does not implement chunked transfer encoding; `curl
  -d` / `--data-binary` always sends a length, so this never comes up in practice.
- **The connection watchdog stays armed across the response.** Cancelling it before the send —
  the obvious place — leaves `.contentProcessed` as the only path to `close()`, so a peer that
  stops reading pins the session, its descriptor and the whole buffered body indefinitely.
- **The listener retries a busy port** with a 2s-to-30s backoff behind a generation counter.
  `NWListener` reports `EADDRINUSE` as `.failed`, not the `.waiting` state the framework
  retries itself — without the retry, a port conflict at launch left Flare deaf for the whole
  session, recoverable only through a Settings change.
- **Overlay windows are ordered out between flashes**, so they cost nothing, but they are
  ordinary windows — they will appear in screen recordings taken during a flash.
- **An interrupted flash is re-run, not dropped.** A screen-parameter or wake notification
  used to kill an in-flight flash outright, and the rate-limit floor then swallowed the retry.
  Wake from sleep is exactly when the flash matters most.
- **The photosensitivity floor uses `CACurrentMediaTime`, not `Date`.** A backwards wall-clock
  step would otherwise make the elapsed interval negative and silently disable flashing.
- **The menu bar keeps the `light.beacon.max` SF Symbol** rather than the app icon. Status
  items need a template image so macOS can tint them for a light or dark menu bar and invert
  them when the menu is open; a full-colour icon cannot do either. The app icon is used for
  Finder, Get Info and the Settings window.
- **Settings sits alone between separators.** macOS assigns the standard Settings item a gear
  automatically and lays the image column out *per section*, so anything sharing a section
  with it inherits a blank 40pt gutter.
- **A submenu parent needs `isEnabled` set explicitly.** `isEnabled = (action != nil)` looks
  right and greys out the whole Pause submenu, because a submenu parent carries no action.
- **Settings shows the listener's live state** next to the port, so a busy port fails loudly
  rather than leaving Flare silently deaf.
- **The Settings window rebuilds its view on every open.** Reopening a cached
  `NSHostingController` does not fire `onAppear` again, so every value it reads once — the
  launch-at-login state, the listener status, "Checked N ago" — would be frozen at whenever
  the window was first built.

## Updates

- **The update check is a check, not an updater.** The original brief ruled out auto-update,
  and this keeps that spirit: no Sparkle, no background download, no self-replacing bundle, no
  third-party dependency. It reads one JSON document and changes a menu item. Everything that
  actually installs remains something you triggered — `brew upgrade`, or a drag from the DMG.
- **It runs hourly but only acts once a day.** A 24-hour timer on a Mac that sleeps would
  simply never fire; comparing elapsed time against a stored timestamp survives sleep.
- **Only a check GitHub answered updates that timestamp.** Stamping on every attempt means a
  DNS failure ten seconds after login — before Wi-Fi has associated, on a login item — counts
  as the day's check and silences the retry for 24 hours. On a Mac restarted daily the
  automatic check could then never once succeed, with no visible symptom.
- **A timestamp in the future is treated as stale.** A bad clock, an NTP step or a plist copied
  off another machine otherwise yields a negative interval that never reaches 24 hours,
  disabling automatic checks permanently across every future launch.
- **The check uses an ephemeral `URLSession`** so nothing lands in the shared cookie,
  credential or URL caches, with a resource timeout so a connection that trickles bytes cannot
  pin the checker at `.checking`.
- **`html_url` from the response is only followed when it is https on github.com.** The
  response chooses which page opens; it should not get to choose the host.

## Packaging

- **The DMG is built with `hdiutil` and Finder AppleScript only** — no `create-dmg` or any
  other third-party tool, matching the app's own zero-dependency rule. Three ordering traps
  are worth knowing if you touch `scripts/make-dmg.sh`:
  - Finder names a disk after its mount point, so a custom `-mountpoint` leaves
    `tell disk "Flare 1.0.0"` unable to find it. Mount under `/Volumes` and read the name back.
  - Finder **deletes** any `.VolumeIcon.icns` on the volume when it opens the window.
  - Closing the window rewrites the volume root's `FinderInfo` and clears the custom-icon bit.

  So the icon copy and `SetFile -a C` both have to come *after* the styling pass, not before.
- **Homebrew ships as a personal tap rather than homebrew-cask.** The official cask
  repository requires notarised binaries and a notability bar a new project will not clear.
  A tap costs two extra commands and behaves identically from then on.
- **The cask uses `postflight_steps`, not the old `postflight` block.** Homebrew 6 deprecated
  arbitrary Ruby in favour of a declarative step list, and paths there are template tokens —
  `{{appdir}}/Flare.app`, not an interpolated `appdir`, and not a `chdir:` symbol. Both of the
  obvious guesses fail silently mid-install with the app still landing in place, so the
  quarantine flag survives and you only find out at first launch.
- **Homebrew 6 refuses to load a cask from an untrusted third-party tap at all**, with or
  without arbitrary Ruby, hence the one-off `brew trust`.
- **`depends_on macos: :sonoma`** — the bare symbol now means "at least"; the old
  `">= :sonoma"` string form is deprecated.
- **The build is native-arch and ad-hoc signed.** For a universal binary, change the Makefile
  to `swift build -c release --arch arm64 --arch x86_64`. For a Developer ID build, replace
  `--sign -` with your identity — and then the cask's quarantine step can go away.

## Changes from the original brief

- **`PostToolUse` lost its `AskUserQuestion` matcher, and `Stop` lost `async`.** Both are
  explained in [claude-code.md](claude-code.md); both were needed to make the specified
  behaviour actually work.
- **The update check exists at all.** The brief said no auto-update and no network beyond
  localhost. The check was added later, deliberately, and is the one thing that talks past
  `127.0.0.1` — off with one toggle.
