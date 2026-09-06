# Flare

A macOS menu bar app that flashes the whole screen when an AI agent is waiting on you.

Notification sounds and banners get missed when several agents are running at once. Flare
paints every display red-orange for a moment instead — on top of full-screen apps, on every
Space — and keeps nagging every couple of minutes until you deal with it.

- One process, no dependencies, no Dock icon, no network beyond `127.0.0.1`.
- Signals arrive over loopback HTTP, so anything that can run `curl` can trigger a flash.
- Built for Claude Code hooks (including sessions run inside [Conductor](https://conductor.build)),
  but nothing about it is Claude-specific.

Requires macOS 14+ and a Swift 5.9+ toolchain (Xcode command line tools).

---

## Install

**Homebrew** — one command, and `brew upgrade` keeps it current:

```sh
brew tap priyomukul/flare https://github.com/priyomukul/flare
brew trust priyomukul/flare
brew install --cask flare
open -a Flare
```

Homebrew 6 asks you to trust any third-party tap before it will load a cask from it — that
is the middle line, and it is a one-off.

**Or the drag-and-drop installer** — grab `Flare-<version>.dmg` from
[Releases](https://github.com/priyomukul/flare/releases), open it, and drag Flare into
Applications.

Flare is ad-hoc signed rather than notarised with a paid Developer ID, so Gatekeeper does
not recognise it. The cask strips the quarantine flag for you. If you install from the DMG
instead, macOS will refuse the first launch — right-click Flare in Applications, choose
**Open**, and confirm once. After that it opens normally.

To uninstall: `brew uninstall --cask flare` (add `--zap` to remove settings too).

### Updates

If you installed with Homebrew, `brew upgrade --cask flare` is all you need.

Either way, Flare checks GitHub once a day for a newer release and, when there is one, the
menu's **Check for Updates…** line becomes **Update to 1.1.0…**. Clicking it opens the release
page — or, on a Homebrew-managed copy, puts `brew upgrade --cask flare` on your clipboard
first. Flare never downloads or installs anything by itself.

That version check is the only thing Flare sends anywhere other than `127.0.0.1`. It is an
unauthenticated `GET` to `api.github.com`, it carries nothing but a `Flare/<version>`
user-agent, and **Settings ▸ Updates ▸ Check for updates automatically** turns it off. With it
off, the menu item still works on demand.

## Build and run

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

---

## Claude Code integration

Open the menu bar item and choose **Copy Claude Code hooks snippet** — it emits the block
below with your current port already filled in. Merge it into the `hooks` object in
`~/.claude/settings.json` (global, so it applies to every project) or `.claude/settings.json`
for one repo.

```json
{
  "hooks": {
    "Notification": [
      { "matcher": "permission_prompt|idle_prompt|elicitation_dialog",
        "hooks": [ { "type": "command", "async": true,
          "command": "curl -s -m 1 -X POST http://127.0.0.1:4242/waiting -H 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1 || true" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command",
          "command": "curl -s -m 1 -X POST http://127.0.0.1:4242/waiting -H 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1 || true" } ] }
    ],
    "PreToolUse": [
      { "matcher": "AskUserQuestion",
        "hooks": [ { "type": "command", "async": true,
          "command": "curl -s -m 1 -X POST http://127.0.0.1:4242/waiting -H 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1 || true" } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command",
          "command": "curl -s -m 1 -X POST http://127.0.0.1:4242/clear -H 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1 || true" } ] }
    ],
    "PostToolUse": [
      { "hooks": [ { "type": "command",
          "command": "curl -s -m 1 -X POST http://127.0.0.1:4242/clear -H 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1 || true" } ] }
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command",
          "command": "curl -s -m 1 -X POST http://127.0.0.1:4242/clear -H 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1 || true" } ] }
    ]
  }
}
```

### Why three "waiting" triggers

No single hook covers every way Claude ends up waiting on you:

| Hook | Catches |
| --- | --- |
| `Notification` | Permission prompts, idle prompts (these only fire after ~60s), elicitation dialogs |
| `Stop` | The end of every turn — Claude is waiting for your next instruction |
| `PreToolUse` on `AskUserQuestion` | Claude asking you a question, which `Notification` does not fire for |

And three that clear: `UserPromptSubmit` (you replied), `PostToolUse` (a tool ran to
completion, which is the only evidence that you answered the permission prompt that raised
the entry), `SessionEnd` (the session is gone).

`PostToolUse` carries no matcher on purpose. If it only cleared on `AskUserQuestion`, then
approving a permission prompt would leave the entry standing and Flare would keep flashing
every two minutes while Claude worked away on exactly what you just allowed. The cost is one
loopback POST — about 10ms — per tool call; narrow it back to `"matcher": "AskUserQuestion"`
if you would rather pay nothing and clear a little later.

`Stop` is not `async`, unlike the other two waiting triggers. The turn has already ended, so
there is no agent latency to protect, and an async POST can land *after* the synchronous
`UserPromptSubmit` clear that follows it — which would strand an agent that then nags forever
with nothing actually waiting.

### Why the commands look like that

- **Nothing is printed to stdout.** `UserPromptSubmit` stdout is injected into Claude's
  context, so a stray line of curl output would end up in the conversation.
- **`|| true` and `-m 1`.** A hook that exits non-zero surfaces an error in Claude Code. If
  Flare is not running, the hook must stay silent and fast rather than complain.
- **`--data-binary @-`** pipes the hook's own stdin payload straight through. Flare reads
  `session_id`, `cwd`, `hook_event_name`, `notification_type`, `message` and `tool_name`
  from it; you do not have to shape anything yourself.
- **`async: true` on `Notification` and `PreToolUse`** so they never sit in the agent's path
  while it is genuinely blocked on you. Everything else runs synchronously: those hooks fire
  when nothing is waiting on the result anyway, and ordering matters more than the
  millisecond.

### Conductor

Conductor runs your local Claude Code, so global hooks in `~/.claude/settings.json` fire
inside Conductor workspaces too. Verify with one session before trusting it: start a
Conductor session, let it ask for a permission, and check that the beacon lights up and the
workspace name appears in the menu. If it does not, fall back to the generic curl below from
whatever wrapper you use.

---

## Use it from anything else

Flare does not care who is calling.

```sh
# something needs you
curl -s -m 1 -X POST http://127.0.0.1:4242/waiting -d '{"agent":"codex-api"}'

# with a note that shows up in the menu
curl -s -m 1 -X POST http://127.0.0.1:4242/waiting \
  -d '{"agent":"codex-api","note":"waiting on a migration decision"}'

# done
curl -s -m 1 -X POST http://127.0.0.1:4242/clear -d '{"agent":"codex-api"}'
```

The `agent` name is the identity — posting `/waiting` twice with the same name refreshes one
entry rather than creating two.

### Terminal bell (optional)

For agents that only ring the bell, point your terminal's bell trigger at `/waiting`.

**iTerm2** — Settings → Profiles → Advanced → Triggers → `+`:
Regular Expression `\a`, Action `Run Command`, Parameters:

```sh
curl -s -m 1 -X POST http://127.0.0.1:4242/waiting -d '{"agent":"terminal"}'
```

**Ghostty** — Ghostty has no trigger system, so wrap the command instead:

```sh
myagent; curl -s -m 1 -X POST http://127.0.0.1:4242/waiting -d '{"agent":"myagent"}'
```

The same works in any shell: append the curl to whatever long-running command you want to be
told about.

---

## HTTP API

Loopback only — `127.0.0.1`, never `0.0.0.0`. Default port 4242, configurable in Settings.

| Route | Does |
| --- | --- |
| `POST /waiting` | Create or refresh a waiting agent, and flash immediately unless paused |
| `POST /clear` | Remove that agent |
| `POST /clear-all` | Remove everything |
| `GET /status` | JSON array of `id`, `name`, `note`, `since` (ISO 8601), `waitingSeconds` |
| `GET /health` | `200 ok` |

Request bodies are JSON in one of two shapes, detected by which fields are present:

**1. Simple** — `{"agent": "name", "note": "optional"}`. The name is the id.

**2. Raw Claude Code hook payload** — piped straight from the hook's stdin. `session_id` is
the id; the name is the last path component of `cwd`; the note is `message`, else
`notification_type`, else `hook_event_name` (with `tool_name` appended when there is one, so
you see `PreToolUse: AskUserQuestion` rather than a bare `PreToolUse`).

An empty or unparseable body is recorded under the id `unknown` rather than being rejected —
a hook that misfires should still get your attention.

```console
$ curl -s http://127.0.0.1:4242/status
[
  {
    "id" : "3f2b9c14-77aa-4e51-9b0d-6c1e2a8f45d7",
    "name" : "api-server",
    "note" : "Claude needs your permission to use Bash",
    "since" : "2026-09-06T20:04:40Z",
    "waitingSeconds" : 37
  }
]
```

`scripts/smoke.sh` exercises every route, including a realistic Claude Code Notification
payload, and prints the resulting `/status`:

```sh
make smoke          # or: scripts/smoke.sh 4242
```

---

## The menu

- **One line per waiting agent** — `api-server · 4m · Claude needs your permission to use Bash`.
  Clicking it clears that agent.
- **Clear all**
- **Test flash** — always flashes, even while paused.
- **Pause ▸ 15 min / 1 hour / until resumed** — collapses to **Resume** while paused. Signals
  are still recorded while paused; resuming flashes at once if anything is waiting.
- **Copy Claude Code hooks snippet** — the block above, with your current port.
- **Settings…**
- **Quit Flare**

## Settings

| Setting | Default | Notes |
| --- | --- | --- |
| Port | 4242 | 1024–65535. Changing it restarts the listener — repaste the hooks snippet. |
| Remind every | 120s | Floor of 30s. |
| Colour | `#FF4500` | Red-orange. |
| Peak opacity | 35% | How solid the flash gets. |
| Check for updates automatically | on | One `GET` to `api.github.com` per day. The only non-localhost traffic Flare produces. |
| Launch at login | off | `SMAppService`; works with the ad-hoc signed bundle. Enable it from an installed copy — a login item pointing into `dist/` dies at the next `make clean`, and Flare says so if you try. |

Settings live in `UserDefaults` under `com.priyomukul.flare`, so you can also poke at them
directly:

```sh
defaults write com.priyomukul.flare reminderInterval -float 30
defaults write com.priyomukul.flare flashColor -string '#00A2FF'
```

Flare picks up changes made from the Settings window immediately; `defaults write` from
outside needs a relaunch.

## What it does when nothing is happening

- **Reminder** — every `reminderInterval` seconds, if anything is still waiting and Flare is
  not paused, it flashes again. The timer re-phases off each flash that actually renders, so a
  signal flash and a nag can never land a fraction of a second apart.
- **Return to desk** — every 5s Flare reads overall input idle time. Once you have been away
  for five minutes it arms, and the moment you touch the machine again it flashes if
  something is still waiting. No permissions needed for this; it is not an event tap.

## Photosensitivity

A flash is two pulses of a solid colour fading in and out over about 1.2 seconds. Flare will
not start a new flash within 0.5s of the last one, so it can never exceed two flashes per
second no matter how many signals arrive at once — well under the three-per-second ceiling.
Turn the peak opacity down if 35% is still too much.

## Checking it yourself

Most of Flare can be checked from a terminal — `make smoke` covers every route, and

```sh
defaults write com.priyomukul.flare reminderInterval -float 30
```

plus one waiting agent will show you the nag loop in half a minute (`defaults delete
com.priyomukul.flare reminderInterval` to put it back).

Two things need you at the keyboard, because they need real hardware events:

- **Full-screen coverage** — put an app in full screen, then `curl -X POST
  http://127.0.0.1:4242/waiting -d '{"agent":"test"}'` from another machine's SSH session or a
  second terminal. The flash should land on top.
- **Display sleep and monitor plug/unplug** — leave an agent waiting, sleep the displays
  (`pmset displaysleepnow`) or unplug an external monitor, then come back. Flare should flash
  once on your return, with no leftover overlay showing on any screen.

---

## Uninstall

1. Quit Flare from the menu bar (turn off **Launch at login** first if you enabled it).
2. Remove it: `brew uninstall --cask flare --zap`, or `rm -rf /Applications/Flare.app` if you
   installed from the DMG.
3. Remove the `hooks` block you pasted into `~/.claude/settings.json`.
4. Optionally `defaults delete com.priyomukul.flare`.

---

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
```

## Choices made along the way

Where the brief left something open, Flare took the simplest option:

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
- **Overlay windows are ordered out between flashes**, so they cost nothing, but they are
  ordinary windows — they will appear in screen recordings taken during a flash.
- **The menu bar keeps the `light.beacon.max` SF Symbol** rather than the app icon. Status
  items need a template image so macOS can tint them for a light or dark menu bar and invert
  them when the menu is open; a full-colour icon cannot do either. The app icon is used for
  Finder, Get Info and the Settings window.
- **Settings shows the listener's live state** next to the port. The brief did not list it,
  but without it a busy port fails silently and Flare just never flashes again.
- **The update check is a check, not an updater.** The brief ruled out auto-update, and this
  keeps that spirit: no Sparkle, no background download, no self-replacing bundle, no
  third-party dependency. It reads one JSON document and changes a menu item. Everything that
  actually installs remains something you triggered — `brew upgrade`, or a drag from the DMG.
- **It runs hourly but only acts once a day.** A 24-hour timer on a Mac that sleeps would
  simply never fire; comparing elapsed time against a stored timestamp survives sleep.
- **The DMG is built with `hdiutil` and Finder AppleScript only** — no `create-dmg` or any
  other third-party tool, matching the app's own zero-dependency rule. Two ordering traps
  are worth knowing if you touch `scripts/make-dmg.sh`: Finder deletes any
  `.VolumeIcon.icns` when it opens the window, and closing the window clears the custom-icon
  bit — so both have to be applied *after* the styling pass, not before.
- **Homebrew ships as a personal tap rather than homebrew-cask.** The official cask
  repository requires notarised binaries and a notability bar a new project will not clear.
  A tap costs two extra commands and behaves identically from then on.
- **The cask uses `postflight_steps`, not the old `postflight` block.** Homebrew 6 deprecated
  arbitrary Ruby in favour of a declarative step list, and paths there are template tokens —
  `{{appdir}}/Flare.app`, not an interpolated `appdir`, and not a `chdir:` symbol. Both of
  the obvious guesses fail silently mid-install with the app still landing in place.
- **The build is native-arch and ad-hoc signed.** For a universal binary, change the Makefile
  to `swift build -c release --arch arm64 --arch x86_64`. For a Developer ID build, replace
  `--sign -` with your identity.
- **`Notification` matches `permission_prompt|idle_prompt|elicitation_dialog`,** the three the
  brief named. Claude Code emits several other types you may want, depending on how you work:
  `elicitation_url_dialog` (an elicitation that wants you to open a URL),
  `quota_auto_resume_stale` / `quota_auto_resume_disabled`, and `agent_needs_input` /
  `agent_completed`. Add any of them to the matcher with `|`.
- **Nothing is wired to `StopFailure`.** A turn that dies on an API error fires `StopFailure`
  rather than `Stop`, so Flare will not flash for it. If you want that — arguably you do, since
  a failed turn is waiting on you as much as a finished one — add a matcher-less `StopFailure`
  entry using the same command as `Stop`.
- **Two changes from the brief's original snippet,** both to make the specified behaviour
  actually work: `PostToolUse` lost its `AskUserQuestion` matcher, and `Stop` lost `async`.
  Both are explained above.

## Troubleshooting

**Nothing flashes.** Check the listener is up: `curl -s http://127.0.0.1:4242/health` should
print `ok`. If the port is in use, the menu shows the error at the top and Settings shows it
next to the port field — pick another port and repaste the snippet.

**Hooks are not firing.** Run `claude --debug` and watch for the hook commands. Confirm your
`~/.claude/settings.json` has one `hooks` object (merged, not two).

**The flash does not cover a full-screen app.** The overlay uses `.screenSaver` window level
with `canJoinAllSpaces` and `fullScreenAuxiliary`, which is enough on macOS 14+. If a
particular app still covers it, that app is running above screen-saver level; there is no
public API above that.

**Launch at login will not enable.** macOS refuses to register login items for bundles it
cannot resolve stably. `make install` and launch from `/Applications`.
