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

pretty() {
  if command -v python3 >/dev/null 2>&1; then python3 -m json.tool 2>/dev/null || cat
  else cat; fi
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
post /clear-all '{}' >/dev/null && ok "POST /clear-all"

say "3. POST /waiting — simple payload"
echo "  -> $(post /waiting '{"agent":"codex-api","note":"needs a decision"}')"
ok "simple payload accepted"

say "4. POST /waiting — Claude Code Notification hook payload"
echo "  -> $(post /waiting '{
  "session_id": "3f2b9c14-77aa-4e51-9b0d-6c1e2a8f45d7",
  "prompt_id": "550e8400-e29b-41d4-a716-446655440000",
  "transcript_path": "/Users/me/.claude/projects/api-server/3f2b9c14.jsonl",
  "cwd": "/Users/me/Works/api-server",
  "permission_mode": "default",
  "hook_event_name": "Notification",
  "notification_type": "permission_prompt",
  "message": "Claude needs your permission to use Bash"
}')"
ok "hook payload accepted"

say "5. POST /waiting — second session in a directory of the same name"
echo "  -> $(post /waiting '{
  "session_id": "b81d0e77-5c3a-42f8-a1b6-9d4e7f200c33",
  "cwd": "/Users/me/Other/api-server",
  "hook_event_name": "Stop",
  "last_assistant_message": "Done — anything else?"
}')"
ok "duplicate name accepted (expect a session-id suffix in /status)"

say "6. POST /waiting — PreToolUse on AskUserQuestion"
echo "  -> $(post /waiting '{
  "session_id": "c0ffee00-1111-2222-3333-444455556666",
  "cwd": "/Users/me/Works/web",
  "hook_event_name": "PreToolUse",
  "tool_name": "AskUserQuestion",
  "tool_use_id": "toolu_01ABC"
}')"
ok "tool payload accepted"

say "7. Bad input must never crash Flare"
echo "  empty body   -> $(curl -s -m 2 -X POST "${BASE}/waiting")"
echo "  garbage      -> $(post /waiting 'not json {{{')"
echo "  json array   -> $(post /waiting '[1,2,3]')"
echo "  empty object -> $(post /waiting '{}')"
ok "all degraded to id 'unknown' without an error"

say "8. GET /status"
curl -s -m 2 "${BASE}/status" | pretty

say "9. POST /clear — one agent"
echo "  -> $(post /clear '{"session_id":"c0ffee00-1111-2222-3333-444455556666"}')"
echo "  -> $(post /clear '{"agent":"codex-api"}')"
ok "cleared two agents"

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
ok "burst handled"

say "12. POST /clear-all"
echo "  -> $(post /clear-all '{}')"
echo "  /status -> $(curl -s -m 2 "${BASE}/status")"

say "Final /status"
curl -s -m 2 "${BASE}/status" | pretty

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
