#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGY_HOOK="$ROOT_DIR/plugin/scripts/agy-hook.sh"

python3 - "$AGY_HOOK" <<'PY'
import json
import os
import shutil
import sys

agy_hook = sys.argv[1]
config_dir = os.path.expanduser("~/.gemini/config")
hooks_path = os.path.join(config_dir, "hooks.json")
backup_path = os.path.join(config_dir, "hooks.json.spywater-bak")

os.makedirs(config_dir, exist_ok=True)

if os.path.exists(hooks_path):
    if not os.path.exists(backup_path):
        shutil.copy2(hooks_path, backup_path)
    with open(hooks_path, "r", encoding="utf-8") as f:
        data = json.load(f)
else:
    data = {}

if not isinstance(data, dict):
    data = {}

data["spywater"] = {
    "SessionStart": [
        {
            "type": "command",
            "command": f"/bin/sh {agy_hook} SessionStart",
            "timeout": 5
        }
    ],
    "PreInvocation": [
        {
            "type": "command",
            "command": f"/bin/sh {agy_hook} PreInvocation",
            "timeout": 5
        }
    ],
    "PostInvocation": [
        {
            "type": "command",
            "command": f"/bin/sh {agy_hook} PostInvocation",
            "timeout": 5
        }
    ],
    "PreToolUse": [
        {
            "matcher": "*",
            "hooks": [
                {
                    "type": "command",
                    "command": f"/bin/sh {agy_hook} PreToolUse",
                    "timeout": 300
                }
            ]
        }
    ],
    "PostToolUse": [
        {
            "matcher": "*",
            "hooks": [
                {
                    "type": "command",
                    "command": f"/bin/sh {agy_hook} PostToolUse",
                    "timeout": 5
                }
            ]
        }
    ],
    "Stop": [
        {
            "type": "command",
            "command": f"/bin/sh {agy_hook} Stop",
            "timeout": 5
        }
    ]
}

with open(hooks_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"Hooks do Antigravity instalados em {hooks_path}")
PY
