#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import json
import os
import sys

config_dir = os.path.expanduser("~/.gemini/config")
hooks_path = os.path.join(config_dir, "hooks.json")
backup_path = os.path.join(config_dir, "hooks.json.spywater-bak")

if not os.path.exists(hooks_path):
    print("~/.gemini/config/hooks.json não encontrado.")
    sys.exit(0)

with open(hooks_path, "r", encoding="utf-8") as f:
    data = json.load(f)

if not isinstance(data, dict) or "spywater" not in data:
    print("Hooks do SpyWater não estavam configurados no Antigravity.")
    sys.exit(0)

data.pop("spywater", None)

if not data and not os.path.exists(backup_path):
    os.remove(hooks_path)
    print("~/.gemini/config/hooks.json removido (vazio).")
else:
    with open(hooks_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("Entrada 'spywater' removida de ~/.gemini/config/hooks.json.")
PY
