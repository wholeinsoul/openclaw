#!/bin/bash
# Task Tracker CLI — atomic task management with file-based locking
# Usage:
#   task.sh add <title> [--type quick|default|coding] [--topic <id>] [--source <msg>]
#   task.sh done <task_id>
#   task.sh stall <task_id>
#   task.sh cancel <task_id>
#   task.sh status <task_id>
#   task.sh dashboard
#   task.sh list [--all]
#
# All mutations acquire a lock, read fresh state, modify, write, then release.
# Dashboard text is printed to stdout for the agent to use in message edit.
#
# Configuration: reads from config.json in the skill directory.
# Copy config.example.json to config.json and fill in your values.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$SKILL_DIR/config.json"
MEMORY_DIR="${OPENCLAW_WORKSPACE:-$(cd "$SKILL_DIR/../../.." && pwd)}/memory"
TASKS_FILE="$MEMORY_DIR/tasks.json"
LOCK_DIR="$MEMORY_DIR/tasks.lock"
STALE_SECONDS=30
MAX_RETRIES=10
RETRY_SLEEP=0.5

# --- Config ---
load_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo '{"error":"config.json not found. Copy config.example.json to config.json and fill in your values."}' >&2
    exit 1
  fi
}

get_config() {
  python3 -c "import json,sys; d=json.load(open('$CONFIG_FILE')); print(d.get('$1',''))"
}

# --- Locking ---
acquire_lock() {
  local retries=$MAX_RETRIES
  while [ $retries -gt 0 ]; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      echo $$ > "$LOCK_DIR/pid"
      date +%s > "$LOCK_DIR/time"
      return 0
    fi
    # Check stale
    if [ -f "$LOCK_DIR/time" ]; then
      local lock_time now age
      lock_time=$(cat "$LOCK_DIR/time" 2>/dev/null || echo 0)
      now=$(date +%s)
      age=$((now - lock_time))
      if [ $age -gt $STALE_SECONDS ]; then
        rm -rf "$LOCK_DIR"
        continue
      fi
    fi
    retries=$((retries - 1))
    sleep $RETRY_SLEEP
  done
  echo '{"error":"Failed to acquire lock after retries"}' >&2
  exit 1
}

release_lock() {
  rm -rf "$LOCK_DIR"
}

trap release_lock EXIT

# --- Helpers ---
now_ms() {
  python3 -c "import time; print(int(time.time()*1000))"
}

ensure_tasks_file() {
  if [ ! -f "$TASKS_FILE" ]; then
    mkdir -p "$MEMORY_DIR"
    load_config
    python3 - "$TASKS_FILE" "$CONFIG_FILE" <<'INIT_PY'
import json, sys
tasks_path, config_path = sys.argv[1], sys.argv[2]
with open(config_path) as f:
    cfg = json.load(f)
data = {
    "version": 3,
    "tasks": {},
    "config": {
        "stallThresholds": cfg.get("stallThresholds", {"quick": 1800000, "coding": 3600000, "default": 1800000}),
        "doneExpiryMs": cfg.get("doneExpiryMs", 86400000),
        "statusEmoji": cfg.get("statusEmoji", {"in_progress": "🔵", "done": "✅", "stalled": "🟡", "cancelled": "⚫"})
    }
}
with open(tasks_path, "w") as f:
    json.dump(data, f, indent=2)
INIT_PY
  fi
}

# --- Commands ---
cmd_add() {
  local title="" type="default" topic="" source=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --type) type="$2"; shift 2;;
      --topic) topic="$2"; shift 2;;
      --source) source="$2"; shift 2;;
      *) title="$title $1"; shift;;
    esac
  done
  title="$(echo "$title" | sed 's/^ *//')"
  [ -z "$title" ] && { echo '{"error":"Title required"}'; exit 1; }

  acquire_lock
  ensure_tasks_file

  local ts
  ts=$(now_ms)
  local task_id="task_${ts}"

  python3 - "$TASKS_FILE" "$task_id" "$title" "$type" "$topic" "$source" "$ts" <<'PYEOF'
import json, sys
path, tid, title, ttype, topic, source, ts = sys.argv[1:8]
with open(path) as f:
    data = json.load(f)
data["tasks"][tid] = {
    "id": tid,
    "title": title,
    "status": "in_progress",
    "type": ttype,
    "createdAt": int(ts),
    "completedAt": None,
    "sourceTopic": topic,
    "source": source
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
print(json.dumps({"ok": True, "taskId": tid, "title": title}))
PYEOF
}

cmd_update_status() {
  local new_status="$1"
  local task_id="$2"

  acquire_lock
  ensure_tasks_file

  python3 - "$TASKS_FILE" "$task_id" "$new_status" <<'PYEOF'
import json, sys, time
path, tid, status = sys.argv[1:4]
with open(path) as f:
    data = json.load(f)
if tid not in data["tasks"]:
    print(json.dumps({"error": f"Task {tid} not found"}))
    sys.exit(1)
data["tasks"][tid]["status"] = status
if status in ("done", "cancelled"):
    data["tasks"][tid]["completedAt"] = int(time.time() * 1000)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
print(json.dumps({"ok": True, "taskId": tid, "status": status}))
PYEOF
}

cmd_dashboard() {
  ensure_tasks_file

  python3 - "$TASKS_FILE" <<'PYEOF'
import json, sys, time
with open(sys.argv[1]) as f:
    data = json.load(f)

cfg = data.get("config", {})
emoji = cfg.get("statusEmoji", {
    "in_progress": "🔵", "done": "✅", "stalled": "🟡", "cancelled": "⚫"
})
expiry = cfg.get("doneExpiryMs", 86400000)
now = time.time() * 1000

lines = []
tasks_sorted = sorted(data["tasks"].values(), key=lambda t: t["createdAt"], reverse=True)

for t in tasks_sorted:
    status = t["status"]
    if status in ("done", "cancelled"):
        completed = t.get("completedAt")
        if completed and (now - completed) > expiry:
            continue
    e = emoji.get(status, "❓")
    lines.append(f"{e} {t['title']}")

if lines:
    print("📋 **Task Dashboard**\n")
    print("\n".join(lines))
else:
    print("📋 **Task Dashboard**\n\n_No active tasks_")
PYEOF
}

cmd_list() {
  ensure_tasks_file
  local show_all="${1:-}"

  python3 - "$TASKS_FILE" "$show_all" <<'PYEOF'
import json, sys, time
with open(sys.argv[1]) as f:
    data = json.load(f)
show_all = sys.argv[2] == "--all" if len(sys.argv) > 2 else False
now = time.time() * 1000
expiry = data.get("config", {}).get("doneExpiryMs", 86400000)

tasks = []
for t in sorted(data["tasks"].values(), key=lambda t: t["createdAt"], reverse=True):
    if not show_all and t["status"] in ("done", "cancelled"):
        completed = t.get("completedAt")
        if completed and (now - completed) > expiry:
            continue
    tasks.append(t)
print(json.dumps(tasks, indent=2))
PYEOF
}

cmd_status() {
  local task_id="$1"
  ensure_tasks_file
  python3 -c "
import json, sys
with open('$TASKS_FILE') as f:
    data = json.load(f)
t = data['tasks'].get('$task_id')
if t:
    print(json.dumps(t, indent=2))
else:
    print(json.dumps({'error': 'Task not found'}))
"
}

# --- Main ---
[ $# -lt 1 ] && { echo "Usage: task.sh <command> [args]"; exit 1; }

CMD="$1"; shift
case "$CMD" in
  add)      cmd_add "$@" ;;
  done)     cmd_update_status "done" "$1" ;;
  stall)    cmd_update_status "stalled" "$1" ;;
  cancel)   cmd_update_status "cancelled" "$1" ;;
  status)   cmd_status "$1" ;;
  dashboard) cmd_dashboard ;;
  list)     cmd_list "${1:-}" ;;
  *)        echo "Unknown command: $CMD"; exit 1 ;;
esac
