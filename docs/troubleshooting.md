# Troubleshooting

**Nothing flashes.** Check the listener is up: `curl -s http://127.0.0.1:4242/health` should
print `ok`. If the port is in use, the menu shows the error at the top and Settings shows it
next to the port field — pick another port and repaste the snippet. Flare retries a busy port
on its own with a 2s-to-30s backoff, so a leftover instance quitting is enough to recover.

**Hooks are not firing.** Run `claude --debug` and watch for the hook commands. Confirm your
`~/.claude/settings.json` has one `hooks` object (merged, not two).

**The flash does not cover a full-screen app.** The overlay uses `.screenSaver` window level
with `canJoinAllSpaces` and `fullScreenAuxiliary`, which is enough on macOS 14+. If a
particular app still covers it, that app is running above screen-saver level; there is no
public API above that.

**Launch at login will not enable.** macOS refuses to register login items for bundles it
cannot resolve stably. Install to `/Applications` — via Homebrew or `make install` — and
enable it from there. A login item pointing into `dist/` dies at the next `make clean`, and
Flare warns you if you try.

**macOS says Flare is damaged or cannot be opened.** Flare is ad-hoc signed rather than
notarised with a paid Developer ID. The Homebrew cask strips the quarantine flag for you; from
a DMG, right-click Flare in Applications, choose **Open**, and confirm once.

**Two copies fighting over the port.** A Homebrew install and a `dist/` build cannot both
listen. `make stop`, or quit the one you are not using.

**An agent nags forever with nothing waiting.** Something posted `/waiting` and nothing ever
cleared it. Click the line in the menu to clear it, or `curl -X POST
http://127.0.0.1:4242/clear-all`. If it keeps happening with Claude Code, check that all three
clearing hooks are present.

---

## Uninstall

1. Quit Flare from the menu bar (turn off **Launch at login** first if you enabled it).
2. Remove it: `brew uninstall --cask flare --zap`, or `rm -rf /Applications/Flare.app` if you
   installed from the DMG.
3. Remove the `hooks` block you pasted into `~/.claude/settings.json`.
4. Optionally `defaults delete com.priyomukul.flare`.
