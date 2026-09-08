# HTTP API

Loopback only — `127.0.0.1`, never `0.0.0.0`. Default port 4242, configurable in Settings.

| Route | Does |
| --- | --- |
| `POST /waiting` | Create or refresh a waiting agent, and flash immediately unless paused |
| `POST /clear` | Remove that agent |
| `POST /clear-all` | Remove everything |
| `GET /status` | JSON array of `id`, `name`, `note`, `since` (ISO 8601), `waitingSeconds` |
| `GET /health` | `200 ok` |

Responses come back in well under a millisecond, so a hook calling this can never stall an
agent.

## Request bodies

JSON in one of two shapes, detected by which fields are present:

**1. Simple** — `{"agent": "name", "note": "optional"}`. The name is the id.

**2. Raw Claude Code hook payload** — piped straight from the hook's stdin. `session_id` is
the id; the name is the last path component of `cwd`; the note is `message`, else
`notification_type`, else `hook_event_name` (with `tool_name` appended when there is one, so
you see `PreToolUse: AskUserQuestion` rather than a bare `PreToolUse`).

An empty or unparseable body is recorded under the id `unknown` rather than being rejected —
a hook that misfires should still get your attention.

If a body somehow contains both an `agent` and a `session_id`, `agent` wins: a caller that
names itself explicitly meant it.

## Request headers

`POST /waiting` reads four optional headers, all of them describing the terminal the caller
is running in. They are what lets the menu raise that window when you click the agent's line;
nothing else uses them, and leaving them off costs you only that.

| Header | Value | Effect |
| --- | --- | --- |
| `X-Flare-Term` | `$TERM_PROGRAM` | Names the terminal app when `X-Flare-App` is absent |
| `X-Flare-App` | `$__CFBundleIdentifier` | The bundle id to raise |
| `X-Flare-Iterm` | `$ITERM_SESSION_ID` | Raises that exact iTerm2 pane |
| `X-Flare-Tty` | `ttys004` or `/dev/ttys004` | Raises that exact Terminal.app tab |

A signal that carries none of them still records the agent; the origin of an earlier signal
for the same id is kept rather than blanked, so one hook without the headers does not undo
what another already established.

```sh
curl -s -m 1 -X POST http://127.0.0.1:4242/waiting \
  -H "X-Flare-App: $__CFBundleIdentifier" \
  -H "X-Flare-Iterm: $ITERM_SESSION_ID" \
  -d '{"agent":"codex-api"}'
```

## Example

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

Two sessions whose directories share a name are disambiguated by the first four characters of
the session id — `api-server (3f2b)`. A simple payload keeps its bare name even in a
collision, since its id *is* its name and `web (web)` would say nothing.

## Status codes

| Situation | Response |
| --- | --- |
| Unknown path | `404` |
| Known path, wrong method | `405` |
| Malformed request, oversized header, bad `Content-Length` | `400` |
| Anything else | `200` |

Query strings and trailing slashes are ignored, so `/status?x=1` and `/health/` both work.

## Checking it

`scripts/smoke.sh` exercises every route — including a realistic Claude Code `Notification`
payload, duplicate directory names, six kinds of bad input and a burst — and prints the
resulting `/status`. Every check asserts on the response; 30 assertions in total.

```sh
make smoke          # or: scripts/smoke.sh 4242
```
