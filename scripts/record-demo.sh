#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT_DIR/plugin/scripts/spy-hook.sh"
AGY_HOOK="$ROOT_DIR/plugin/scripts/agy-hook.sh"
PORT="${SPYWATER_PORT:-47821}"
BASE="http://127.0.0.1:$PORT"
RAW_OUT="${1:-$HOME/Desktop/spywater-linkedin-demo.mp4}"
mkdir -p "$(dirname "$RAW_OUT")"
OUT_MP4="$(cd "$(dirname "$RAW_OUT")" && pwd)/$(basename "$RAW_OUT")"
OUT_SRT="${OUT_MP4%.mp4}.srt"
DURATION="${DEMO_DURATION:-24}"

if [ ! -f "$HOOK" ] || [ ! -f "$AGY_HOOK" ]; then
  echo "Erro: scripts de hook não encontrados em $ROOT_DIR/plugin/scripts" >&2
  exit 1
fi

echo "Compilando SpyWater (modo demo em inglês)…"
swift build --package-path "$ROOT_DIR/app" -c release
DEMO_BIN="$ROOT_DIR/app/.build/release/SpyWater"
if [ ! -x "$DEMO_BIN" ]; then
  echo "Erro: binário compilado não encontrado em $DEMO_BIN" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spywater-demo.XXXXXX")"
DEMO_REPO="/tmp/spywater-demo-repo"
MISSIONS_FILE="$HOME/.spywater/missions.json"
RATE_CACHE_FILE="$HOME/.spywater/rate-limits-cache.json"
MISSIONS_BAK=""
RATE_CACHE_BAK=""
MISSION_SHORT_ID=""
APP_PID=""
REC_PID=""
BG_PIDS=""

cleanup() {
  trap - EXIT INT TERM

  if [ -n "$REC_PID" ] && kill -0 "$REC_PID" 2>/dev/null; then
    kill -INT "$REC_PID" 2>/dev/null || true
    wait "$REC_PID" 2>/dev/null || true
  fi

  for pid in $BG_PIDS; do
    pkill -TERM -P "$pid" 2>/dev/null || true
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done

  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    kill -TERM "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi

  if [ -n "$MISSIONS_BAK" ] && [ -f "$MISSIONS_BAK" ]; then
    mkdir -p "$HOME/.spywater"
    cp "$MISSIONS_BAK" "$MISSIONS_FILE"
  else
    rm -f "$MISSIONS_FILE"
  fi

  if [ -n "$RATE_CACHE_BAK" ] && [ -f "$RATE_CACHE_BAK" ]; then
    mkdir -p "$HOME/.spywater"
    cp "$RATE_CACHE_BAK" "$RATE_CACHE_FILE"
  else
    rm -f "$RATE_CACHE_FILE"
  fi

  if [ -n "$MISSION_SHORT_ID" ]; then
    rm -rf "$HOME/.spywater/worktrees/$MISSION_SHORT_ID" 2>/dev/null || true
  fi

  rm -rf "$DEMO_REPO" "$TMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

if [ -f "$MISSIONS_FILE" ]; then
  MISSIONS_BAK="$TMP_DIR/missions.json.bak"
  cp "$MISSIONS_FILE" "$MISSIONS_BAK"
  rm -f "$MISSIONS_FILE"
fi

if [ -f "$RATE_CACHE_FILE" ]; then
  RATE_CACHE_BAK="$TMP_DIR/rate-limits-cache.json.bak"
  cp "$RATE_CACHE_FILE" "$RATE_CACHE_BAK"
  rm -f "$RATE_CACHE_FILE"
fi

# Repositório Git isolado para a demonstração de Missão paralela
rm -rf "$DEMO_REPO"
mkdir -p "$DEMO_REPO"
git -C "$DEMO_REPO" init -b main >/dev/null 2>&1 || git -C "$DEMO_REPO" init >/dev/null
git -C "$DEMO_REPO" config user.name "SpyWater Demo"
git -C "$DEMO_REPO" config user.email "demo@spywater.local"
cat >"$DEMO_REPO/README.md" <<'MD'
# Billing API Demo
Demo repository for SpyWater multi-agent Mission orchestrator.
MD
git -C "$DEMO_REPO" add README.md
git -C "$DEMO_REPO" commit -m "chore: initial commit" >/dev/null

# Mock do Claude CLI para dividir e executar o DAG paralelo com timing previsível
FAKE_CLAUDE="$TMP_DIR/fake-claude.sh"
cat >"$FAKE_CLAUDE" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

ARGS="$*"
if [[ "$ARGS" == *"--json-schema"* ]]; then
  cat <<'JSON'
{"structured_output":{"title":"Billing API + Auth + Stripe","tasks":[{"id":"T1","title":"Core database schema & migrations","prompt":"Create schema.sql with users and invoices tables","depends_on":[],"verify_command":"test -f schema.sql"},{"id":"T2","title":"JWT auth middleware","prompt":"Implement JWT middleware in auth.ts","depends_on":["T1"],"verify_command":"test -f auth.ts"},{"id":"T3","title":"Stripe webhook processor","prompt":"Implement webhook handler in webhooks.ts","depends_on":["T1"],"verify_command":"test -f webhooks.ts"},{"id":"T4","title":"End-to-end integration tests","prompt":"Add end-to-end tests in tests.spec.ts","depends_on":["T2","T3"],"verify_command":"test -f tests.spec.ts"}]}}
JSON
  exit 0
fi

case "$ARGS" in
  *"Sua tarefa (T1)"*)
    sleep 1.4
    echo "-- schema" > schema.sql
    ;;
  *"Sua tarefa (T2)"*)
    sleep 3.0
    echo "// auth" > auth.ts
    ;;
  *"Sua tarefa (T3)"*)
    sleep 3.4
    echo "// webhooks" > webhooks.ts
    ;;
  *"Sua tarefa (T4)"*)
    sleep 1.6
    echo "// tests" > tests.spec.ts
    ;;
esac

echo '{"type":"assistant","session_id":"demo-mission-worker","message":{"content":[{"type":"text","text":"Task completed successfully"}]}}'
echo '{"type":"result","session_id":"demo-mission-worker","result":"ok","is_error":false}'
exit 0
SH
chmod +x "$FAKE_CLAUDE"

# Helper Swift compilado antes da gravação (ativação do processo, bounds da janela e clique em abas via AX)
HELPER_SRC="$TMP_DIR/demo-helper.swift"
HELPER_BIN="$TMP_DIR/demo-helper"
cat >"$HELPER_SRC" <<'SWIFT'
import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else { exit(1) }

switch args[1] {
case "activate":
    guard args.count >= 3, let pid = Int32(args[2]) else { exit(1) }
    if let app = NSRunningApplication(processIdentifier: pid) {
        let ok = app.activate(options: [.activateIgnoringOtherApps])
        exit(ok ? 0 : 1)
    }
    exit(1)

case "rect":
    let targetPid = args.count >= 3 ? (Int32(args[2]) ?? -1) : -1
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
        for win in list {
            let layer = win[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            let owner = win[kCGWindowOwnerName as String] as? String
            let pid = win[kCGWindowOwnerPID as String] as? Int
            let pidMatch = targetPid > 0 && pid.map(Int32.init) == targetPid
            guard pidMatch || owner == "SpyWater" else { continue }
            guard let bounds = win[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width >= 500
            else { continue }
            let x = max(0, Int(floor(rect.origin.x)) - 12)
            let y = max(0, Int(floor(rect.origin.y)) - 12)
            let w = Int(ceil(rect.width)) + 24
            let h = Int(ceil(rect.height)) + 24
            print("\(x),\(y),\(w),\(h)")
            exit(0)
        }
    }
    exit(1)

case "click":
    guard args.count >= 4, let pid = Int32(args[2]) else { exit(1) }
    let target = args[3]
    let app = AXUIElementCreateApplication(pid)

    func axAttr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var out: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &out) == .success ? out : nil
    }

    func axStr(_ el: AXUIElement, _ name: String) -> String? {
        axAttr(el, name) as? String
    }

    func axChildren(_ el: AXUIElement) -> [AXUIElement] {
        (axAttr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    func hasPressAction(_ el: AXUIElement) -> Bool {
        var actionsRef: CFArray?
        guard AXUIElementCopyActionNames(el, &actionsRef) == .success,
              let actions = actionsRef as? [String]
        else { return false }
        return actions.contains(kAXPressAction)
    }

    func matches(_ el: AXUIElement, depth: Int = 0) -> Bool {
        for key in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
            if let s = axStr(el, key)?.trimmingCharacters(in: .whitespacesAndNewlines),
               s == target || s.hasPrefix(target + " ") || s.hasPrefix(target + ",") {
                return true
            }
        }
        if depth < 2 {
            for child in axChildren(el) {
                if matches(child, depth: depth + 1) {
                    return true
                }
            }
        }
        return false
    }

    var queue: [AXUIElement] = [app]
    var visited = 0
    while !queue.isEmpty && visited < 400 {
        let el = queue.removeFirst()
        visited += 1
        let role = axStr(el, kAXRoleAttribute) ?? ""
        if (role == kAXButtonRole || role == kAXRadioButtonRole || hasPressAction(el)) && matches(el) {
            if AXUIElementPerformAction(el, kAXPressAction as CFString) == .success {
                exit(0)
            }
        }
        queue.append(contentsOf: axChildren(el))
    }
    exit(1)

default:
    exit(1)
}
SWIFT

HAS_HELPER=0
if swiftc -O -o "$HELPER_BIN" "$HELPER_SRC" >/dev/null 2>&1; then
  HAS_HELPER=1
fi

get_window_rect() {
  if [ "$HAS_HELPER" -eq 1 ]; then
    "$HELPER_BIN" rect "$APP_PID" 2>/dev/null || true
  fi
}

click_tab() {
  local tab_name="$1"
  if [ "$HAS_HELPER" -eq 1 ] && "$HELPER_BIN" click "$APP_PID" "$tab_name" >/dev/null 2>&1; then
    return 0
  fi
  printf '\n\033[1;33m👉 Click the "%s" tab in SpyWater now!\033[0m\n' "$tab_name"
  return 0
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

echo "Iniciando SpyWater em modo demo (EN)…"
pkill -x SpyWater 2>/dev/null || true
sleep 0.4

SPYWATER_DEBUG=1 SPYWATER_DEMO=1 SPYWATER_LANG=en SPYWATER_CLAUDE_BIN="$FAKE_CLAUDE" "$DEMO_BIN" >"$TMP_DIR/spywater.log" 2>&1 &
APP_PID=$!

SERVER_UP=0
for _ in $(seq 1 60); do
  if curl -sf --max-time 2 "$BASE/health" >/dev/null 2>&1; then
    SERVER_UP=1
    break
  fi
  sleep 0.1
done

if [ "$SERVER_UP" -ne 1 ]; then
  echo "Erro: servidor HTTP do SpyWater não respondeu em $BASE/health" >&2
  cat "$TMP_DIR/spywater.log" >&2 || true
  exit 1
fi

sleep 0.4
if [ "$HAS_HELPER" -eq 1 ]; then
  "$HELPER_BIN" activate "$APP_PID" 2>/dev/null || true
fi

osascript - "$APP_PID" <<'OSA' 2>/dev/null || true
on run argv
    set targetPid to (item 1 of argv) as integer
    try
        tell application "System Events"
            set p to first process whose unix id is targetPid
            set frontmost of p to true
            if (count of windows of p) > 0 then
                set position of window 1 of p to {160, 80}
                set size of window 1 of p to {960, 740}
            end if
        end tell
    end try
end run
OSA

sleep 0.4

# Popula rate limits e métricas antes de começar a gravar
STATUS_JSON="$(python3 - <<'PY'
import json, time
now = int(time.time())
payload = {
    "session_id": "demo-claude-1",
    "workspace": {"current_dir": "/Users/leonardocruz/Projects/billing-api"},
    "model": {"display_name": "Opus 4.6"},
    "context_window": {
        "used_percentage": 42.0,
        "context_window_size": 200000,
        "total_input_tokens": 84000,
    },
    "cost": {"total_cost_usd": 1.84},
    "rate_limits": {
        "five_hour": {"used_percentage": 34.0, "resets_at": now + 9600},
        "seven_day": {"used_percentage": 48.0, "resets_at": now + 345600},
    },
}
print(json.dumps(payload))
PY
)"
curl -sf --max-time 3 -H 'Content-Type: application/json' -d "$STATUS_JSON" "$BASE/statusline" >/dev/null

# Sessão 1: Claude Code trabalhando
printf '%s' '{"session_id":"demo-claude-1","cwd":"/Users/leonardocruz/Projects/billing-api","hook_event_name":"SessionStart","source":"startup","model":"claude-opus-4-6","session_title":"Stripe Webhook & Migrations"}' | /bin/sh "$HOOK" event >/dev/null
printf '%s' '{"session_id":"demo-claude-1","cwd":"/Users/leonardocruz/Projects/billing-api","hook_event_name":"UserPromptSubmit","prompt":"Add Stripe webhook idempotency & run Prisma migration"}' | /bin/sh "$HOOK" event >/dev/null
printf '%s' '{"session_id":"demo-claude-1","cwd":"/Users/leonardocruz/Projects/billing-api","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"src/stripe/webhooks.ts"}}' | /bin/sh "$HOOK" event >/dev/null

# Sessão 2: Antigravity / Gemini trabalhando
printf '%s' '{"conversationId":"demo-agy-1","workspacePaths":["/Users/leonardocruz/Projects/analytics-ui"],"modelName":"gemini-3-pro-high","lastUserInput":"Add cohort retention stacked chart to analytics-ui"}' | /bin/sh "$AGY_HOOK" PreInvocation >/dev/null
printf '%s' '{"conversationId":"demo-agy-1","workspacePaths":["/Users/leonardocruz/Projects/analytics-ui"],"modelName":"gemini-3-pro-high","toolCall":{"name":"read_file","args":{"Path":"src/charts/RetentionChart.tsx"}}}' | /bin/sh "$AGY_HOOK" PreToolUse >/dev/null

# Sessão 3: Claude Code pronta (idle)
printf '%s' '{"session_id":"demo-claude-2","cwd":"/Users/leonardocruz/Projects/auth-service","hook_event_name":"SessionStart","source":"startup","model":"claude-sonnet-4-6","session_title":"JWT Token Rotation"}' | /bin/sh "$HOOK" event >/dev/null

sleep 0.8

RECT="$(get_window_rect)"
TMP_MOV="$TMP_DIR/spywater-raw.mov"

if [ -n "$RECT" ]; then
  echo "Gravando janela do SpyWater ($RECT) por ${DURATION}s…"
  screencapture -v "-R$RECT" "-V$DURATION" -x "$TMP_MOV" >/dev/null 2>&1 &
else
  echo "Gravando tela inteira (região da janela indisponível) por ${DURATION}s…"
  screencapture -v "-V$DURATION" -x "$TMP_MOV" >/dev/null 2>&1 &
fi
REC_PID=$!

# 0s - 5.5s: Working agents (cyan/emerald animation + corner mascot)
sleep 2.5
printf '%s' '{"session_id":"demo-claude-1","cwd":"/Users/leonardocruz/Projects/billing-api","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm run test:webhooks"}}' | /bin/sh "$HOOK" event >/dev/null
printf '%s' '{"conversationId":"demo-agy-1","workspacePaths":["/Users/leonardocruz/Projects/analytics-ui"],"modelName":"gemini-3-pro-high","toolCall":{"name":"edit_file","args":{"Path":"src/charts/RetentionChart.tsx"}}}' | /bin/sh "$AGY_HOOK" PreToolUse >/dev/null
sleep 3.0

# 5.5s - 11.5s: "Needs you" cards (coral/amber pulse + ! mascot) -> live approval
printf '%s' '{"session_id":"demo-claude-1","cwd":"/Users/leonardocruz/Projects/billing-api","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"npx prisma migrate deploy --schema=./prisma/schema.prisma"}}' | /bin/sh "$HOOK" wait >/dev/null &
BG_PIDS="$BG_PIDS $!"

sleep 1.5

AGY_Q='{"conversationId":"demo-agy-1","workspacePaths":["/Users/leonardocruz/Projects/analytics-ui"],"modelName":"gemini-3-pro-high","toolCall":{"name":"ask_question","args":{"questions":[{"question":"Deploy analytics-ui to staging after checks pass?","options":["Yes, deploy to staging","Keep local for review"],"is_multi_select":false}]}}}'
printf '%s' "$AGY_Q" | /bin/sh "$AGY_HOOK" PreToolUse >/dev/null &
BG_PIDS="$BG_PIDS $!"

sleep 2.5

# Inicia Missão paralela ao fundo antes de trocar para a aba Missions
MISSION_RESP="$(curl -sf --max-time 5 -H 'Content-Type: application/json' \
  -d "{\"goal\":\"Build billing API with JWT auth, Stripe webhooks, and integration tests\",\"projectPath\":\"$DEMO_REPO\",\"maxWorkers\":3,\"permissionMode\":\"autonomous\"}" \
  "$BASE/debug/mission" || echo '{}')"
MISSION_SHORT_ID="$(python3 - "$MISSION_RESP" <<'PY' 2>/dev/null || true
import json, sys
mid = json.loads(sys.argv[1]).get("id", "")
print(mid.replace("-", "").lower()[:8])
PY
)"

if ID_BASH="$(poll_pending_id Bash)"; then
  curl -sf --max-time 3 -H 'Content-Type: application/json' \
    -d "{\"id\":\"$ID_BASH\",\"action\":\"allow\"}" \
    "$BASE/debug/decide" >/dev/null || true
fi

sleep 0.8

if ID_AGY_Q="$(poll_pending_id ask_question)"; then
  DECIDE_Q="$(python3 - "$ID_AGY_Q" <<'PY'
import json, sys
print(json.dumps({
    "id": sys.argv[1],
    "action": "answer",
    "answers": {"Deploy analytics-ui to staging after checks pass?": "Yes, deploy to staging"},
}))
PY
)"
  curl -sf --max-time 3 -H 'Content-Type: application/json' \
    -d "$DECIDE_Q" \
    "$BASE/debug/decide" >/dev/null || true
fi

sleep 0.7

# 11.5s - 18.5s: Missions tab with DAG and parallel git worktrees
click_tab "Missions"
sleep 7.0

# 18.5s - 24s: Plan Usage tab
click_tab "Plan Usage"
wait "$REC_PID" 2>/dev/null || true
REC_PID=""

if [ ! -s "$TMP_MOV" ]; then
  echo "" >&2
  echo "Erro: a gravação de tela não gerou arquivo de vídeo ($TMP_MOV)." >&2
  echo "Verifique em Ajustes do Sistema → Privacidade e Segurança → Gravação de Tela" >&2
  echo "se o seu Terminal/IDE tem permissão para gravar a tela e tente novamente." >&2
  exit 1
fi

# Gera arquivo de legendas em inglês (.srt) junto ao vídeo para o LinkedIn
cat >"$OUT_SRT" <<'SRT'
1
00:00:00,200 --> 00:00:05,300
Monitor Claude Code & Antigravity agents live in one native macOS app

2
00:00:05,500 --> 00:00:11,300
Instant alerts when an agent needs permission or your input

3
00:00:11,500 --> 00:00:18,300
Multi-agent Missions: split tasks & run parallel Claude Code worktrees

4
00:00:18,500 --> 00:00:23,800
Track 5h / 7d plan limits, tokens, and costs in a dedicated Usage tab
SRT

FINAL_FILE=""
if command -v ffmpeg >/dev/null 2>&1; then
  FFMPEG_FILTERS="$(ffmpeg -hide_banner -filters 2>/dev/null || true)"
  BURNED=0

  if printf '%s\n' "$FFMPEG_FILTERS" | grep -qE '(^|[[:space:]])subtitles([[:space:]]|$)'; then
    echo "Convertendo para MP4 com legendas em inglês embutidas (subtitles)…"
    cp "$OUT_SRT" "$TMP_DIR/captions.srt"
    if (cd "$TMP_DIR" && ffmpeg -y -loglevel error -i "$TMP_MOV" \
      -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2,subtitles=captions.srt:force_style='FontName=Helvetica Neue,FontSize=15,PrimaryColour=&H00FFFFFF,BackColour=&H9908101E,BorderStyle=4,Outline=0,Shadow=0,Alignment=2,MarginV=20'" \
      -c:v libx264 -pix_fmt yuv420p -profile:v high -crf 18 -preset slow \
      -movflags +faststart \
      "$OUT_MP4" 2>/dev/null); then
      BURNED=1
    fi
  elif printf '%s\n' "$FFMPEG_FILTERS" | grep -qE '(^|[[:space:]])drawtext([[:space:]]|$)'; then
    echo "Convertendo para MP4 com legendas em inglês embutidas (drawtext)…"
    DRAW_VF="scale=trunc(iw/2)*2:trunc(ih/2)*2"
    DRAW_VF="$DRAW_VF,drawtext=text='Monitor Claude Code & Antigravity agents live in one native macOS app':fontcolor=white:fontsize=20:box=1:boxcolor=0x08101e@0.82:boxborderw=10:x=(w-text_w)/2:y=h-th-28:enable='between(t,0.2,5.3)'"
    DRAW_VF="$DRAW_VF,drawtext=text='Instant alerts when an agent needs permission or your input':fontcolor=white:fontsize=20:box=1:boxcolor=0x08101e@0.82:boxborderw=10:x=(w-text_w)/2:y=h-th-28:enable='between(t,5.5,11.3)'"
    DRAW_VF="$DRAW_VF,drawtext=text='Multi-agent Missions\: split tasks & run parallel Claude Code worktrees':fontcolor=white:fontsize=20:box=1:boxcolor=0x08101e@0.82:boxborderw=10:x=(w-text_w)/2:y=h-th-28:enable='between(t,11.5,18.3)'"
    DRAW_VF="$DRAW_VF,drawtext=text='Track 5h / 7d plan limits, tokens, and costs in a dedicated Usage tab':fontcolor=white:fontsize=20:box=1:boxcolor=0x08101e@0.82:boxborderw=10:x=(w-text_w)/2:y=h-th-28:enable='between(t,18.5,23.8)'"
    if ffmpeg -y -loglevel error -i "$TMP_MOV" \
      -vf "$DRAW_VF" \
      -c:v libx264 -pix_fmt yuv420p -profile:v high -crf 18 -preset slow \
      -movflags +faststart \
      "$OUT_MP4" 2>/dev/null; then
      BURNED=1
    fi
  fi

  if [ "$BURNED" -ne 1 ]; then
    echo "Convertendo para MP4 (H.264 otimizado para LinkedIn; use $OUT_SRT como legenda)…"
    ffmpeg -y -loglevel error -i "$TMP_MOV" \
      -c:v libx264 -pix_fmt yuv420p -profile:v high -crf 18 -preset slow \
      -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -movflags +faststart \
      "$OUT_MP4"
  fi
  FINAL_FILE="$OUT_MP4"
elif command -v avconvert >/dev/null 2>&1; then
  echo "Convertendo para MP4 via avconvert (use $OUT_SRT como legenda no LinkedIn)…"
  avconvert --source "$TMP_MOV" --output "$OUT_MP4" --preset PresetHighestQuality --replace >/dev/null
  FINAL_FILE="$OUT_MP4"
else
  FINAL_FILE="${OUT_MP4%.mp4}.mov"
  cp "$TMP_MOV" "$FINAL_FILE"
fi

echo "Vídeo pronto: $FINAL_FILE"
echo "Legenda (.srt): $OUT_SRT"
open -R "$FINAL_FILE" 2>/dev/null || true
