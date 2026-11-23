#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEE_SCRIPT="$ROOT_DIR/plugin/scripts/statusline-tee.sh"

python3 - "$TEE_SCRIPT" <<'PY'
import json
import os
import shutil
import sys

tee_script = sys.argv[1]
settings_path = os.path.expanduser("~/.claude/settings.json")
backup_path = os.path.expanduser("~/.claude/settings.json.spywater-bak")
spy_dir = os.path.expanduser("~/.spywater")
orig_file = os.path.join(spy_dir, "statusline-original")

os.makedirs(os.path.dirname(settings_path), exist_ok=True)
os.makedirs(spy_dir, exist_ok=True)

if os.path.exists(settings_path):
    if not os.path.exists(backup_path):
        shutil.copy2(settings_path, backup_path)
    with open(settings_path, "r", encoding="utf-8") as f:
        data = json.load(f)
else:
    data = {}

sl = data.get("statusLine")
current_cmd = ""
new_sl = {"type": "command"}

if isinstance(sl, dict):
    current_cmd = sl.get("command") or ""
    new_sl.update(sl)
elif isinstance(sl, str):
    current_cmd = sl

if "statusline-tee.sh" in current_cmd:
    print("Status line do SpyWater já instalado.")
    sys.exit(0)

with open(orig_file, "w", encoding="utf-8") as f:
    f.write(current_cmd)

new_sl["type"] = "command"
new_sl["command"] = tee_script
data["statusLine"] = new_sl

with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"Status line atualizado com wrapper: {tee_script}")
PY
