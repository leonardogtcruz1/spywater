#!/bin/sh
# usage: agy-hook.sh <EventName>
PORT="${SPYWATER_PORT:-47821}"
EVENT="${1:-SessionStart}"
if [ "$EVENT" = "PreToolUse" ]; then MAXT=300; else MAXT=2; fi

TMP=$(mktemp "${TMPDIR:-/tmp}/agyhook.XXXXXX") || {
  if [ "$EVENT" = "PreToolUse" ] || [ "$EVENT" = "Stop" ]; then
    printf '{"decision":"allow"}'
  else
    printf '{}'
  fi
  exit 0
}
CPID=""
trap 'rm -f "$TMP"' EXIT
trap '[ -n "$CPID" ] && kill "$CPID" 2>/dev/null; rm -f "$TMP"; exit 0' INT TERM

curl -sS -f --connect-timeout 0.3 --max-time "$MAXT" \
  -H 'Content-Type: application/json' \
  -H "X-Spy-Event: $EVENT" -H "X-Spy-PPID: $PPID" \
  --data-binary @- "http://127.0.0.1:$PORT/hook/agy" <&0 >"$TMP" 2>/dev/null &
CPID=$!
wait "$CPID" 2>/dev/null
RC=$?

if [ "$RC" -eq 7 ] && [ -f "$HOME/.spywater/autolaunch" ] && [ -d "$HOME/Applications/SpyWater.app" ]; then
  open -g "$HOME/Applications/SpyWater.app" </dev/null >/dev/null 2>&1 &
fi

if [ -s "$TMP" ]; then
  cat "$TMP"
else
  if [ "$EVENT" = "PreToolUse" ] || [ "$EVENT" = "Stop" ]; then
    printf '{"decision":"allow"}'
  else
    printf '{}'
  fi
fi
exit 0
