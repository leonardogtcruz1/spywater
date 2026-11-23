#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT_DIR/plugin/scripts/spy-hook.sh"
AGY_HOOK="$ROOT_DIR/plugin/scripts/agy-hook.sh"
PORT="${SPYWATER_PORT:-47821}"
BASE="http://127.0.0.1:$PORT"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0

report_pass() {
  echo "PASS: $1"
  PASS=$((PASS + 1))
}

report_fail() {
  echo "FAIL: $1 ($2)"
  FAIL=$((FAIL + 1))
}

poll_pending_id() {
  local want_tool="${1:-}"
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ]; do
    local res
    res="$(curl -sf --max-time 3 "$BASE/pending" 2>/dev/null || echo '[]')"
    local found
    found="$(python3 - "$res" "$want_tool" <<'PY'
import json, sys
items = json.loads(sys.argv[1])
want = sys.argv[2]
for item in items:
    if not want or item.get("toolName") == want:
        print(item["id"])
        break
PY
)"
    if [ -n "$found" ]; then
      printf '%s' "$found"
      return 0
    fi
    sleep 0.1
  done
  return 1
}

# Wait briefly for health endpoint
for _ in $(seq 1 30); do
  if curl -sf --max-time 3 "$BASE/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

# 1. /health
HEALTH="$(curl -s --max-time 3 "$BASE/health" || true)"
if python3 - "$HEALTH" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d.get("ok") is True, d
PY
then
  report_pass "1. GET /health"
else
  report_fail "1. GET /health" "got: $HEALTH"
fi

# 2. Async SessionStart + PreToolUse(Bash)
OUT_ASYNC_1="$(printf '%s' '{"session_id":"selftest-sess-1","cwd":"/tmp/proj","hook_event_name":"SessionStart","source":"startup","model":"claude-test"}' | /bin/sh "$HOOK" event)"
OUT_ASYNC_2="$(printf '%s' '{"session_id":"selftest-sess-1","cwd":"/tmp/proj","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"}}' | /bin/sh "$HOOK" event)"
if [ -z "$OUT_ASYNC_1" ] && [ -z "$OUT_ASYNC_2" ]; then
  report_pass "2. Async SessionStart + PreToolUse(Bash)"
else
  report_fail "2. Async SessionStart + PreToolUse(Bash)" "non-empty output: $OUT_ASYNC_1 $OUT_ASYNC_2"
fi

# 3. Blocking PermissionRequest -> allow
OUT3="$TMP_DIR/out3.json"
printf '%s' '{"session_id":"selftest-sess-1","cwd":"/tmp/proj","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"echo hi"}}' | /bin/sh "$HOOK" wait >"$OUT3" &
PID3=$!
if ID3="$(poll_pending_id Bash)"; then
  curl -sf --max-time 3 -H 'Content-Type: application/json' -d "{\"id\":\"$ID3\",\"action\":\"allow\"}" "$BASE/debug/decide" >/dev/null
  wait "$PID3" || true
  if python3 - "$OUT3" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    got = json.load(f)
expected = {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow"}}}
assert got == expected, f"got {got} != {expected}"
PY
  then
    report_pass "3. PermissionRequest allow"
  else
    report_fail "3. PermissionRequest allow" "unexpected output: $(cat "$OUT3")"
  fi
else
  pkill -TERM -P "$PID3" 2>/dev/null || true
  kill "$PID3" 2>/dev/null || true
  report_fail "3. PermissionRequest allow" "pending item did not appear"
fi

# 4. Blocking PreToolUse(AskUserQuestion) -> answer
OUT4="$TMP_DIR/out4.json"
Q_PAYLOAD='{"session_id":"selftest-sess-1","cwd":"/tmp/proj","hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Qual framework?","header":"Stack","options":[{"label":"React","description":"UI"},{"label":"Vue","description":"Web"}],"multiSelect":false}]}}'
printf '%s' "$Q_PAYLOAD" | /bin/sh "$HOOK" wait >"$OUT4" &
PID4=$!
if ID4="$(poll_pending_id AskUserQuestion)"; then
  curl -sf --max-time 3 -H 'Content-Type: application/json' -d "{\"id\":\"$ID4\",\"action\":\"answer\",\"answers\":{\"Qual framework?\":\"React\"}}" "$BASE/debug/decide" >/dev/null
  wait "$PID4" || true
  if python3 - "$OUT4" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    got = json.load(f)
h = got["hookSpecificOutput"]
assert h["hookEventName"] == "PreToolUse", h
assert h["permissionDecision"] == "allow", h
ui = h["updatedInput"]
assert ui["answers"] == {"Qual framework?": "React"}, ui
assert len(ui["questions"]) == 1 and ui["questions"][0]["question"] == "Qual framework?", ui
PY
  then
    report_pass "4. AskUserQuestion answer"
  else
    report_fail "4. AskUserQuestion answer" "unexpected output: $(cat "$OUT4")"
  fi
else
  pkill -TERM -P "$PID4" 2>/dev/null || true
  kill "$PID4" 2>/dev/null || true
  report_fail "4. AskUserQuestion answer" "pending item did not appear"
fi

# 5. Release test -> empty output
OUT5="$TMP_DIR/out5.json"
printf '%s' '{"session_id":"selftest-sess-1","cwd":"/tmp/proj","hook_event_name":"PermissionRequest","tool_name":"Write","tool_input":{"file_path":"/tmp/a.txt","content":"x"}}' | /bin/sh "$HOOK" wait >"$OUT5" &
PID5=$!
if ID5="$(poll_pending_id Write)"; then
  curl -sf --max-time 3 -H 'Content-Type: application/json' -d "{\"id\":\"$ID5\",\"action\":\"release\"}" "$BASE/debug/decide" >/dev/null
  wait "$PID5" || true
  if [ ! -s "$OUT5" ]; then
    report_pass "5. Release -> empty output"
  else
    report_fail "5. Release -> empty output" "got: $(cat "$OUT5")"
  fi
else
  pkill -TERM -P "$PID5" 2>/dev/null || true
  kill "$PID5" 2>/dev/null || true
  report_fail "5. Release -> empty output" "pending item did not appear"
fi

# 6. Client-gone test -> kill hook process, /pending empties within 2s
printf '%s' '{"session_id":"selftest-sess-1","cwd":"/tmp/proj","hook_event_name":"PermissionRequest","tool_name":"Read","tool_input":{"file_path":"/tmp/b.txt"}}' | /bin/sh "$HOOK" wait >/dev/null &
PID6=$!
if ID6="$(poll_pending_id Read)"; then
  pkill -TERM -P "$PID6" 2>/dev/null || true
  kill -TERM "$PID6" 2>/dev/null || true
  wait "$PID6" 2>/dev/null || true
  CLEARED=0
  for _ in $(seq 1 20); do
    PEND="$(curl -sf --max-time 3 "$BASE/pending" 2>/dev/null || echo '[]')"
    if python3 - "$PEND" "$ID6" <<'PY'
import json, sys
items = json.loads(sys.argv[1])
sys.exit(0 if all(i.get("id") != sys.argv[2] for i in items) else 1)
PY
    then
      CLEARED=1
      break
    fi
    sleep 0.1
  done
  if [ "$CLEARED" -eq 1 ]; then
    report_pass "6. Client-gone cleanup"
  else
    report_fail "6. Client-gone cleanup" "pending still present after 2s"
  fi
else
  pkill -TERM -P "$PID6" 2>/dev/null || true
  kill "$PID6" 2>/dev/null || true
  report_fail "6. Client-gone cleanup" "pending item did not appear"
fi

# 7. Origin header rejected with 403
CODE7="$(curl -s --max-time 3 -o /dev/null -w '%{http_code}' -H 'Origin: http://evil' -H 'Content-Type: application/json' -d '{"session_id":"s1","hook_event_name":"Stop"}' "$BASE/hook")"
if [ "$CODE7" = "403" ]; then
  report_pass "7. Origin header 403"
else
  report_fail "7. Origin header 403" "got HTTP $CODE7"
fi

# 8. Antigravity PreToolUse(read_file) -> immediate allow
OUT8="$(printf '%s' '{"conversationId":"agy-test-1","workspacePaths":["/tmp/agy"],"modelName":"gemini-4-neon-high","toolCall":{"name":"read_file","args":{"Path":"/tmp/a"}}}' | /bin/sh "$AGY_HOOK" PreToolUse)"
if python3 - "$OUT8" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d.get("decision") == "allow", d
PY
then
  report_pass "8. Antigravity PreToolUse(read_file) allow"
else
  report_fail "8. Antigravity PreToolUse(read_file) allow" "got: $OUT8"
fi

# 9. Antigravity PreToolUse(ask_question) -> answer via deny+reason
OUT9="$TMP_DIR/out9.json"
AGY_Q='{"conversationId":"agy-test-1","workspacePaths":["/tmp/agy"],"modelName":"gemini-4-neon-high","toolCall":{"name":"ask_question","args":{"questions":[{"question":"Qual DB?","options":["Postgres","SQLite"],"is_multi_select":false}]}}}'
printf '%s' "$AGY_Q" | /bin/sh "$AGY_HOOK" PreToolUse >"$OUT9" &
PID9=$!
if ID9="$(poll_pending_id ask_question)"; then
  curl -sf --max-time 3 -H 'Content-Type: application/json' -d "{\"id\":\"$ID9\",\"action\":\"answer\",\"answers\":{\"Qual DB?\":\"Postgres\"}}" "$BASE/debug/decide" >/dev/null
  wait "$PID9" || true
  if python3 - "$OUT9" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    got = json.load(f)
assert got.get("decision") == "deny", got
assert "Postgres" in got.get("reason", ""), got
PY
  then
    report_pass "9. Antigravity ask_question answer"
  else
    report_fail "9. Antigravity ask_question answer" "unexpected output: $(cat "$OUT9")"
  fi
else
  pkill -TERM -P "$PID9" 2>/dev/null || true
  kill "$PID9" 2>/dev/null || true
  report_fail "9. Antigravity ask_question answer" "pending item did not appear"
fi

# 10. Antigravity PreToolUse(ask_permission) -> allow (auto_approve) and release (allow)
OUT10A="$TMP_DIR/out10a.json"
AGY_P='{"conversationId":"agy-test-1","workspacePaths":["/tmp/agy"],"modelName":"gemini-4-neon-high","toolCall":{"name":"ask_permission","args":{"Action":"write","Target":"/etc/hosts","Reason":"Edit hosts"}}}'
printf '%s' "$AGY_P" | /bin/sh "$AGY_HOOK" PreToolUse >"$OUT10A" &
PID10A=$!
OK10A=0
if ID10A="$(poll_pending_id ask_permission)"; then
  curl -sf --max-time 3 -H 'Content-Type: application/json' -d "{\"id\":\"$ID10A\",\"action\":\"allow\"}" "$BASE/debug/decide" >/dev/null
  wait "$PID10A" || true
  if python3 - "$OUT10A" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    got = json.load(f)
assert got.get("decision") == "auto_approve", got
PY
  then
    OK10A=1
  fi
else
  pkill -TERM -P "$PID10A" 2>/dev/null || true
  kill "$PID10A" 2>/dev/null || true
fi

OUT10B="$TMP_DIR/out10b.json"
printf '%s' "$AGY_P" | /bin/sh "$AGY_HOOK" PreToolUse >"$OUT10B" &
PID10B=$!
OK10B=0
if ID10B="$(poll_pending_id ask_permission)"; then
  curl -sf --max-time 3 -H 'Content-Type: application/json' -d "{\"id\":\"$ID10B\",\"action\":\"release\"}" "$BASE/debug/decide" >/dev/null
  wait "$PID10B" || true
  if python3 - "$OUT10B" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    got = json.load(f)
assert got.get("decision") == "allow", got
PY
  then
    OK10B=1
  fi
else
  pkill -TERM -P "$PID10B" 2>/dev/null || true
  kill "$PID10B" 2>/dev/null || true
fi

if [ "$OK10A" -eq 1 ] && [ "$OK10B" -eq 1 ]; then
  report_pass "10. Antigravity ask_permission allow + release"
else
  report_fail "10. Antigravity ask_permission allow + release" "okA=$OK10A okB=$OK10B outA=$(cat "$OUT10A" 2>/dev/null || true) outB=$(cat "$OUT10B" 2>/dev/null || true)"
fi

echo "Summary: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
