# Claude Code integration

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

## Why three "waiting" triggers

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

## Why the commands look like that

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

## Conductor

[Conductor](https://conductor.build) runs your local Claude Code, so global hooks in
`~/.claude/settings.json` fire inside Conductor workspaces too. Verify with one session before
trusting it: start a Conductor session, let it ask for a permission, and check that the beacon
lights up and the workspace name appears in the menu. If it does not, fall back to the generic
curl in [integrations.md](integrations.md) from whatever wrapper you use.

## Events Flare does not subscribe to

- **`Notification` matches `permission_prompt|idle_prompt|elicitation_dialog`.** Claude Code
  emits several other types you may want, depending on how you work:
  `elicitation_url_dialog` (an elicitation that wants you to open a URL),
  `quota_auto_resume_stale` / `quota_auto_resume_disabled`, and `agent_needs_input` /
  `agent_completed`. Add any of them to the matcher with `|`.
- **Nothing is wired to `StopFailure`.** A turn that dies on an API error fires `StopFailure`
  rather than `Stop`, so Flare will not flash for it. If you want that — arguably you do, since
  a failed turn is waiting on you as much as a finished one — add a matcher-less `StopFailure`
  entry using the same command as `Stop`.
