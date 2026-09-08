# Configuration and behaviour

## The menu

- **One line per waiting agent** — `api-server · 4m · Claude needs your permission to use Bash`.
  Clicking it raises the terminal window that agent is waiting in, then clears it. iTerm2 and
  Terminal.app land on the exact tab; other terminals get the app brought forward. See
  [claude-code.md](claude-code.md#the-x-flare-headers) for what makes that possible, and
  [troubleshooting.md](troubleshooting.md) if nothing comes forward.
- **Clear all**
- **Test flash** — always flashes, even while paused.
- **Pause ▸ 15 min / 1 hour / until resumed** — collapses to **Resume** while paused. Signals
  are still recorded while paused; resuming flashes at once if anything is waiting.
- **Copy Claude Code hooks snippet** — the block from [claude-code.md](claude-code.md), with
  your current port.
- **Settings…**
- **About Flare** — version, developer, and a link to the repo.
- **Quit Flare**

## Settings

| Setting | Default | Notes |
| --- | --- | --- |
| Port | 4242 | 1024–65535. Changing it restarts the listener — repaste the hooks snippet. |
| Remind every | 120s | Floor of 30s. |
| Colour | `#FF4500` | Red-orange. |
| Peak opacity | 20% | How solid the flash gets. |
| Menu bar badge | Number | `Number` shows how many agents are waiting; `Dot` shows only that some are, in the flash colour. |
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
- **Pause** — signals are still recorded, nothing flashes. An expired timed pause behaves like
  Resume: it flashes immediately if something is waiting, which is the point of pausing for
  fifteen minutes.

## Photosensitivity

A flash is two pulses of a solid colour fading in and out over about 1.2 seconds. Flare will
not start a new flash within 0.5s of the last one, so it can never exceed two flashes per
second no matter how many signals arrive at once — well under the three-per-second ceiling.
Turn the peak opacity down if 20% is still too much.

## Updates

If you installed with Homebrew, `brew upgrade --cask flare` is all you need.

Either way, Flare checks GitHub once a day for a newer release and reports it in **Settings ▸
Updates**, where **Check Now** runs a check on demand and **Get it** opens the release page —
or, on a Homebrew-managed copy, puts `brew upgrade --cask flare` on your clipboard first.
Flare never downloads or installs anything by itself.

That version check is the only thing Flare sends anywhere other than `127.0.0.1`. It is an
unauthenticated `GET` to `api.github.com` on an ephemeral URLSession — no cookies, no
credentials, no cache — carrying nothing but a `Flare/<version>` user-agent. **Settings ▸
Updates ▸ Check for updates automatically** turns it off; with it off, **Check Now** still
works on demand.

"Once a day" means once per *answer*. A check that never reached GitHub does not count, and is
retried on the next hourly tick rather than a day later — otherwise a login item that starts
ten seconds after boot, before Wi-Fi has associated, would fail once and then stay quiet until
tomorrow.
