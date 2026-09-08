# Changelog

All notable changes to Flare are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Flare uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Clicking an agent in the menu raises the terminal it is waiting in**, then clears it.
  iTerm2 and Terminal.app land on the exact tab; other terminals are brought to the front.
  This needs the current hooks snippet — recopy it from **Copy Claude Code hooks snippet** and
  repaste, because the three "waiting" commands now send four `X-Flare-*` headers describing
  the terminal they ran in. The headers are used for nothing else and never leave `127.0.0.1`;
  delete them and everything still works except the raising. macOS asks once for permission to
  control your terminal.

### Fixed

- **Clearing from the menu now counts as being at your desk.** `Clear all` and clicking an
  agent left the return-to-desk trigger armed, so with two agents waiting, clearing one could
  flash for the other moments later.

## [1.0.1] — 2026-09-08

### Added

- **Update checking.** Flare asks GitHub once a day whether a newer release exists and reports
  it in **Settings ▸ Updates**, with **Check Now** on demand and **Get it** to open the release
  page — or, on a Homebrew-managed copy, to put `brew upgrade --cask flare` on the clipboard.
  It never downloads or installs anything itself. The check is an unauthenticated `GET` to
  `api.github.com` on an ephemeral URLSession, and it is the only thing Flare sends anywhere
  other than `127.0.0.1`. **Check for updates automatically** turns it off.
- **About Flare**, above Quit in the menu: version, developer, and a link to the repository.
- **Menu bar badge style** (**Settings ▸ Menu bar**). `Number` keeps the count of waiting
  agents; `Dot` shows only that something is waiting, drawn in the flash colour.

### Changed

- **The flash no longer draws a badge.** The black label in the top-right said who was waiting
  for the second it was on screen; the menu and the tooltip say the same thing on your own
  schedule, and without landing over what you were reading.
- **Default peak opacity is 20%**, down from 35%. Existing installs keep whatever they set.
- **Check for Updates… left the menu.** Updates live in Settings, which has room for the
  status line, the buttons and the Homebrew hint.
- **README is a README again.** The manual it had grown into now lives under
  [docs/](docs/), split by what you would be looking for.

### Fixed

- **A failed update check no longer burns the day.** The timestamp was stamped before the
  response was examined, so a check that learned nothing counted as the day's check. On a Mac
  that is restarted daily — the check fires ten seconds after launch, routinely before Wi-Fi
  has associated — the automatic check could never once succeed. Only an answered check
  stamps it now; attempts are floored at 15 minutes.
- **A future-dated timestamp no longer disables update checks permanently.** A bad clock, an
  NTP step or a plist restored from another machine made the elapsed interval negative, which
  never reaches 24 hours. A negative interval now reads as stale.
- **Settings stops going stale.** The window cached its hosting controller, so reopening it
  showed the listener status, "Checked N ago" and the launch-at-login state as they were when
  it was first built. It builds a fresh view every time.
- **The Homebrew cask works on Homebrew 6**, which deprecated the `postflight` block in favour
  of `postflight_steps`.

## [1.0.0] — 2026-09-07

Initial release. A menu bar app that flashes the screen when an AI agent is waiting on you:
a loopback HTTP listener on port 4242, one line per waiting agent in the menu, nag flashes
every couple of minutes until you answer, pause, and a Homebrew cask.

[Unreleased]: https://github.com/priyomukul/flare/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/priyomukul/flare/releases/tag/v1.0.1
[1.0.0]: https://github.com/priyomukul/flare/releases/tag/v1.0.0
