---
name: task-tracker
description: Track all tasks on a pinned messaging dashboard. Add tasks before starting work, update the dashboard, then do the work. Handles concurrent updates with file locking.
metadata: {"openclaw": {"always": true}}
---

# Task Tracker

Track every task on a pinned dashboard message. This is mandatory for ALL tasks from the user.

## Setup

1. Copy `config.example.json` to `config.json` in this skill directory
2. Fill in your channel, group ID, topic ID, and pinned message ID
3. The config is gitignored — your personal data stays local

## Protocol (EVERY TASK — NO EXCEPTIONS)

1. **ADD** the task (get task_id back)
2. **EDIT** the dashboard message with fresh output
3. **DO** the actual work
4. **SEND** results to the user in the source topic/channel
5. **DONE** — update status ONLY after results are sent
6. **EDIT** the dashboard again

⚠️ Never mark done before the reply is sent. Dashboard = reality, not intent.

## Commands

All commands use `{baseDir}/scripts/task.sh`. The script handles locking internally (mkdir-based, 30s stale timeout).

### Add a task
```bash
bash {baseDir}/scripts/task.sh add "Task title" --type default --topic 1 --source "msg#123"
```
Returns: `{"ok": true, "taskId": "task_17393...", "title": "..."}`

Types: `quick` (30min stall), `default` (30min), `coding` (60min)

### Complete a task
```bash
bash {baseDir}/scripts/task.sh done <task_id>
```

### Mark as stalled (needs user input)
```bash
bash {baseDir}/scripts/task.sh stall <task_id>
```

### Cancel a task
```bash
bash {baseDir}/scripts/task.sh cancel <task_id>
```

### Get dashboard text
```bash
bash {baseDir}/scripts/task.sh dashboard
```
Prints formatted dashboard text. Use this output to edit the pinned message.

### List tasks
```bash
bash {baseDir}/scripts/task.sh list         # active + recent
bash {baseDir}/scripts/task.sh list --all   # everything
```

## Dashboard Update

Read config values from `{baseDir}/config.json`, then edit with the `message` tool:
```
action: edit
channel: <config.channel>
target: <config.groupId>
threadId: <config.dashboardTopicId>
messageId: <config.dashboardMessageId>
message: <output from dashboard command>
```

## Statuses

| Emoji | Status | Meaning |
|-------|--------|---------|
| 🔵 | in_progress | Actively working |
| ✅ | done | Completed (expires after 24h) |
| 🟡 | stalled | Blocked — needs user feedback |
| ⚫ | cancelled | Abandoned |

## Rules

- Dashboard shows ONLY emoji + title per line, newest first
- Done/cancelled tasks auto-expire after 24h
- ALL work output goes to the source topic — NEVER to the dashboard topic
- Concurrent updates are safe — the script acquires a lock before any mutation
- tasks.json persists to disk — survives gateway restarts
- Always run `dashboard` command fresh before editing the message (never compose from memory)
