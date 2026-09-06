#!/usr/bin/env bash
# Exercises every Flare route against a running instance and prints the
# resulting /status. Usage: scripts/smoke.sh [port]
set -uo pipefail

PORT="${1:-${FLARE_PORT:-4242}}"
BASE="http://127.0.0.1:${PORT}"
PASS=0
FAIL=0

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { PASS=$((PASS+1)); printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }

# expect <description> <expected-status> <curl args...>
expect() {
  local desc="$1" want="$2"; shift 2
  local got
  got=$(curl -s -o /dev/null -w '%{http_code}' -m 2 "$@")
  if [ "$got" = "$want" ]; then ok "$desc ($got)"; else bad "$desc — wanted $want, got $got"; fi
}

post() { curl -s -m 2 -X POST -H 'Content-Type: application/json' --data-binary "$2" "${BASE}$1"; }

# assert <description> <substring> <actual>
assert() {
  local desc="$1" want="$2" got="$3"
  case "$got" in
    *"$want"*) ok "$desc" ;;
    *)         bad "$desc — wanted a body containing '$want', got: ${got:-<empty>}" ;;
  esac
}

pretty() {
  local input; input=$(cat)
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$input" | python3 -m json.tool 2>/dev/null || printf '%s\n' "$input"
  else
    printf '%s\n' "$input"
  fi
}

say "Flare smoke test — ${BASE}"
if ! curl -s -m 2 "${BASE}/health" >/dev/null; then
  echo "  Flare is not answering on ${BASE}. Start it with: make run" >&2
  exit 1
fi

say "1. GET /health"
expect "health returns 200" 200 "${BASE}/health"
[ "$(curl -s -m 2 "${BASE}/health")" = "ok" ] && ok "body is 'ok'" || bad "body is not 'ok'"

say "2. Clean slate"
assert "POST /clear-all empties the store" '"waiting":0' "$(post /clear-all '{}')"

say "3. POST /waiting — simple payload"
R=$(post /waiting '{"agent":"codex-api","note":"needs a decision"}'); echo "  -> $R"
assert "simple payload keyed by agent name" '"id":"codex-api"' "$R"

say "4. POST /waiting — Claude Code Notification hook payload"
R=$(post /waiting '{
  "session_id": "3f2b9c14-77aa-4e51-9b0d-6c1e2a8f45d7",
  "prompt_id": "550e8400-e29b-41d4-a716-446655440000",
  "transcript_path": "/Users/me/.claude/projects/api-server/3f2b9c14.jsonl",
  "cwd": "/Users/me/Works/api-server",
  "permission_mode": "default",
  "hook_event_name": "Notification",
  "notification_type": "permission_prompt",
  "message": "Claude needs your permission to use Bash"
}'); echo "  -> $R"
assert "hook payload keyed by session_id" '"id":"3f2b9c14-77aa-4e51-9b0d-6c1e2a8f45d7"' "$R"

say "5. POST /waiting — second session in a directory of the same name"
R=$(post /waiting '{
  "session_id": "b81d0e77-5c3a-42f8-a1b6-9d4e7f200c33",
  "cwd": "/Users/me/Other/api-server",
  "hook_event_name": "Stop",
  "last_assistant_message": "Done — anything else?"
}'); echo "  -> $R"
assert "second session in a same-named directory is its own entry" '"waiting":3' "$R"

say "6. POST /waiting — PreToolUse on AskUserQuestion"
R=$(post /waiting '{
  "session_id": "c0ffee00-1111-2222-3333-444455556666",
  "cwd": "/Users/me/Works/web",
  "hook_event_name": "PreToolUse",
  "tool_name": "AskUserQuestion",
  "tool_use_id": "toolu_01ABC"
}'); echo "  -> $R"
assert "PreToolUse payload accepted" '"id":"c0ffee00-1111-2222-3333-444455556666"' "$R"

say "7. Bad input must never crash Flare"
for body in "" 'not json {{{' '[1,2,3]' '{}' '{"agent":5}' '{"agent":"   "}'; do
  R=$(post /waiting "$body")
  printf '  %-16s -> %s\n' "${body:-<empty>}" "$R"
  assert "'${body:-<empty>}' degrades to id unknown" '"id":"unknown"' "$R"
done
assert "Flare is still alive after bad input" "ok" "$(curl -s -m 2 "${BASE}/health")"

say "8. GET /status"
STATUS=$(curl -s -m 2 "${BASE}/status")
printf '%s' "$STATUS" | pretty
assert "duplicate directory names are disambiguated by session id" 'api-server (3f2b)' "$STATUS"
assert "the other one too" 'api-server (b81d)' "$STATUS"
assert "tool_name lands in the note" 'PreToolUse: AskUserQuestion' "$STATUS"
assert "since is ISO 8601" '"since" : "20' "$STATUS"
assert "waitingSeconds is present" 'waitingSeconds' "$STATUS"

say "9. POST /clear — one agent"
R=$(post /clear '{"session_id":"c0ffee00-1111-2222-3333-444455556666"}'); echo "  -> $R"
assert "clearing by session_id drops one" '"waiting":4' "$R"
R=$(post /clear '{"agent":"codex-api"}'); echo "  -> $R"
assert "clearing by agent name drops one" '"waiting":3' "$R"

say "10. Status codes"
expect "unknown path is 404" 404 "${BASE}/nope"
expect "GET /waiting is 405" 405 "${BASE}/waiting"
expect "POST /status is 405" 405 -X POST "${BASE}/status"
expect "query strings are ignored" 200 "${BASE}/status?x=1"
expect "trailing slash is ignored" 200 "${BASE}/health/"

say "11. Speed — 20 sequential /waiting calls"
start=$(python3 -c 'import time;print(time.time())' 2>/dev/null || echo 0)
for i in $(seq 1 20); do post /waiting "{\"agent\":\"bench-$i\"}" >/dev/null; done
python3 -c "import time;print(f'  20 calls in {(time.time()-$start)*1000:.0f}ms total')" 2>/dev/null || true
assert "all 20 landed" '"waiting":23' "$(curl -s -m 2 -X POST "${BASE}/waiting" -d '{"agent":"bench-1"}')"
assert "re-posting an existing agent refreshes rather than duplicates" '"waiting":23' "$(post /waiting '{"agent":"bench-20"}')"

say "12. POST /clear-all"
R=$(post /clear-all '{}'); echo "  -> $R"
assert "clear-all empties the store" '"waiting":0' "$R"

say "Final /status"
STATUS=$(curl -s -m 2 "${BASE}/status")
printf '%s\n' "$STATUS"
[ "$STATUS" = "[]" ] && ok "/status is an empty array" || bad "/status should be [] , got: $STATUS"

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
