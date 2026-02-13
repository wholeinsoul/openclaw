# Task Tracker

An [OpenClaw](https://openclaw.ai) skill that tracks tasks on a pinned messaging dashboard (Telegram, Discord, etc.).

## Features

- **Pinned dashboard** — a single message that always shows current task status
- **Strict task lifecycle** — add → work → deliver → complete → update dashboard
- **Concurrent-safe** — file-based locking prevents race conditions
- **Auto-expiry** — completed/cancelled tasks disappear after 24h
- **Configurable** — thresholds, emoji, and channel settings via `config.json`

## Setup

1. Install the skill into your OpenClaw workspace under `skills/task-tracker/`
2. Copy `config.example.json` to `config.json`:
   ```bash
   cp config.example.json config.json
   ```
3. Edit `config.json` with your values:
   - `channel` — messaging platform (`telegram`, `discord`, `slack`, etc.)
   - `groupId` — your group/channel ID
   - `dashboardTopicId` — topic/thread ID for the dashboard message
   - `dashboardMessageId` — the pinned message ID to edit
4. Pin a message in your group and note its message ID

## Task Types

| Type | Stall Threshold | Use For |
|------|----------------|---------|
| `quick` | 30 min | Fast lookups, questions |
| `default` | 30 min | Standard tasks |
| `coding` | 60 min | Development work |

## Statuses

| Emoji | Status | Meaning |
|-------|--------|---------|
| 🔵 | in_progress | Actively working |
| ✅ | done | Completed |
| 🟡 | stalled | Blocked — needs user input |
| ⚫ | cancelled | Abandoned |

## Requirements

- Python 3 (for JSON manipulation)
- Bash
- OpenClaw with a messaging channel configured

## License

MIT
