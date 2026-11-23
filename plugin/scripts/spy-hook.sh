#!/bin/sh
# usage: spy-hook.sh event|wait
PORT="${SPYWATER_PORT:-47821}"
MODE="${1:-event}"
if [ "$MODE" = "wait" ]; then MAXT=86400; else MAXT=3; fi
OUT=$(curl -sS -f --connect-timeout 0.3 --max-time "$MAXT" \
  -H 'Content-Type: application/json' \
  -H "X-Spy-Mode: $MODE" -H "X-Spy-PPID: $PPID" -H "X-Spy-Term: ${TERM_PROGRAM:-}" \
  --data-binary @- "http://127.0.0.1:$PORT/hook" 2>/dev/null)
RC=$?
if [ $RC -eq 7 ] && [ -f "$HOME/.spywater/autolaunch" ] && [ -d "$HOME/Applications/SpyWater.app" ]; then
  open -g "$HOME/Applications/SpyWater.app" >/dev/null 2>&1 &
fi
[ -n "$OUT" ] && printf '%s' "$OUT"
exit 0
