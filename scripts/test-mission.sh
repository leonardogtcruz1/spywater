#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BIN="$HOME/Applications/SpyWater.app/Contents/MacOS/SpyWater"
BASE="http://127.0.0.1:${SPYWATER_PORT:-47821}"

TEST_REPO="/tmp/spyw-mission-test-repo"
FAKE_CLAUDE="/tmp/spyw-fake-claude.sh"
MISSIONS_FILE="$HOME/.spywater/missions.json"
MISSIONS_BAK=""
APP_PID=""

cleanup() {
  if [ -n "$APP_PID" ]; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_REPO" "$FAKE_CLAUDE"
  if [ -n "$MISSIONS_BAK" ] && [ -f "$MISSIONS_BAK" ]; then
    mv "$MISSIONS_BAK" "$MISSIONS_FILE"
  elif [ -z "$MISSIONS_BAK" ]; then
    rm -f "$MISSIONS_FILE"
  fi
}
trap cleanup EXIT

if [ -f "$MISSIONS_FILE" ]; then
  MISSIONS_BAK="$(mktemp)"
  cp "$MISSIONS_FILE" "$MISSIONS_BAK"
fi

rm -rf "$TEST_REPO" "$FAKE_CLAUDE"
mkdir -p "$TEST_REPO"

cat >"$FAKE_CLAUDE" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

ARGS="$*"
if [[ "$ARGS" == *"--json-schema"* ]]; then
  cat <<'JSON'
{"structured_output":{"title":"App Teste Paralelo","tasks":[{"id":"T1","title":"Base core","prompt":"Crie core.txt","depends_on":[],"verify_command":"test -f core.txt"},{"id":"T2","title":"Feature A","prompt":"Crie feature_a.txt","depends_on":["T1"],"verify_command":"test -f feature_a.txt"},{"id":"T3","title":"Feature B","prompt":"Crie feature_b.txt","depends_on":["T1"],"verify_command":"test -f feature_b.txt"}]}}
JSON
  exit 0
fi

case "$ARGS" in
  *"Sua tarefa (T1)"*)
    echo "core ok" > core.txt
    ;;
  *"Sua tarefa (T2)"*)
    sleep 0.4
    echo "feature A ok" > feature_a.txt
    ;;
  *"Sua tarefa (T3)"*)
    sleep 0.4
    echo "feature B ok" > feature_b.txt
    ;;
esac

echo '{"type":"assistant","session_id":"fake-mission-sess","message":{"content":[{"type":"text","text":"Tarefa concluída"}]}}'
echo '{"type":"result","session_id":"fake-mission-sess","result":"ok","is_error":false}'
exit 0
SH
chmod +x "$FAKE_CLAUDE"

pkill -x SpyWater 2>/dev/null || true
sleep 0.3

SPYWATER_DEBUG=1 SPYWATER_CLAUDE_BIN="$FAKE_CLAUDE" "$APP_BIN" >/tmp/spywater-mission-debug.log 2>&1 &
APP_PID=$!

for _ in $(seq 1 40); do
  if curl -sf --max-time 2 "$BASE/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

"$ROOT_DIR/scripts/selftest.sh"

RESP="$(curl -sf --max-time 5 -H 'Content-Type: application/json' \
  -d "{\"goal\":\"Build parallel test app\",\"projectPath\":\"$TEST_REPO\",\"maxWorkers\":2,\"permissionMode\":\"autonomous\"}" \
  "$BASE/debug/mission")"

MISSION_ID="$(python3 - "$RESP" <<'PY'
import json, sys
print(json.loads(sys.argv[1])["id"])
PY
)"
echo "Started mission: $MISSION_ID"

STATUS=""
for _ in $(seq 1 300); do
  LIST="$(curl -sf --max-time 3 "$BASE/debug/missions" || echo '[]')"
  STATUS="$(python3 - "$LIST" "$MISSION_ID" <<'PY'
import json, sys
for m in json.loads(sys.argv[1]):
    if m.get("id") == sys.argv[2]:
        print(m.get("status", ""))
        break
PY
)"
  if [ "$STATUS" = "completed" ] || [ "$STATUS" = "failed" ]; then
    break
  fi
  sleep 0.1
done

if [ "$STATUS" != "completed" ]; then
  echo "FAIL: Mission ended with status=$STATUS"
  curl -sf --max-time 3 "$BASE/debug/missions" || true
  exit 1
fi

for f in core.txt feature_a.txt feature_b.txt; do
  if [ ! -f "$TEST_REPO/$f" ]; then
    echo "FAIL: Missing merged file $TEST_REPO/$f"
    exit 1
  fi
done

WT_COUNT="$(git -C "$TEST_REPO" worktree list | wc -l | tr -d ' ')"
if [ "$WT_COUNT" -ne 1 ]; then
  echo "FAIL: Expected 1 git worktree after cleanup, got $WT_COUNT"
  git -C "$TEST_REPO" worktree list
  exit 1
fi

echo "PASS: Mission DAG + parallel worktree merge ($TEST_REPO)"
