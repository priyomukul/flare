# Changelog

All notable changes to Flare are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Flare uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

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

[1.0.1]: https://github.com/priyomukul/flare/releases/tag/v1.0.1
[1.0.0]: https://github.com/priyomukul/flare/releases/tag/v1.0.0
