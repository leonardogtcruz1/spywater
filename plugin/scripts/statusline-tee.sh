#!/bin/sh
INPUT=$(cat)
( printf '%s' "$INPUT" | curl -s --connect-timeout 0.2 --max-time 1 -H 'Content-Type: application/json' \
    --data-binary @- "http://127.0.0.1:${SPYWATER_PORT:-47821}/statusline" >/dev/null 2>&1 & )
ORIG_FILE="$HOME/.spywater/statusline-original"
if [ -s "$ORIG_FILE" ]; then printf '%s' "$INPUT" | sh -c "$(cat "$ORIG_FILE")"; fi
