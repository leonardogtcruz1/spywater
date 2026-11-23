#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import json
import os
import sys

settings_path = os.path.expanduser("~/.claude/settings.json")
orig_file = os.path.expanduser("~/.spywater/statusline-original")

if not os.path.exists(settings_path):
    print("~/.claude/settings.json não encontrado.")
    sys.exit(0)

with open(settings_path, "r", encoding="utf-8") as f:
    data = json.load(f)

sl = data.get("statusLine")
current_cmd = sl.get("command", "") if isinstance(sl, dict) else (sl if isinstance(sl, str) else "")

if "statusline-tee.sh" not in current_cmd:
    print("Status line não está usando o wrapper do SpyWater.")
    sys.exit(0)

orig_cmd = ""
if os.path.exists(orig_file):
    with open(orig_file, "r", encoding="utf-8") as f:
        orig_cmd = f.read().strip()

if orig_cmd:
    if isinstance(sl, dict):
        sl["command"] = orig_cmd
        data["statusLine"] = sl
    else:
        data["statusLine"] = {"type": "command", "command": orig_cmd}
else:
    data.pop("statusLine", None)

with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")

print("Status line original restaurado.")
PY
