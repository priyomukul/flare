# Using Flare from anything else

Flare does not care who is calling. Anything that can run `curl` can trigger a flash.

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

See [http-api.md](http-api.md) for every route and both payload shapes.

## Terminal bell

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

## Shell helpers

A pair of functions is often enough:

```sh
flare()       { curl -s -m 1 -X POST "http://127.0.0.1:4242/waiting" -d "{\"agent\":\"$1\",\"note\":\"${2:-}\"}" >/dev/null 2>&1 || true; }
flare-clear() { curl -s -m 1 -X POST "http://127.0.0.1:4242/clear"   -d "{\"agent\":\"$1\"}" >/dev/null 2>&1 || true; }

# long build finished, come look
make deploy; flare deploy "finished, needs a sanity check"
```
