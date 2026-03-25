# macOS Memory Health Check

Automated memory monitoring and cleanup for macOS. Detects memory pressure, swap thrashing, and bloated apps — then optionally fixes them.

## Quick Start

```bash
# Make scripts executable
chmod +x mem-check.sh install.sh

# Run a one-time check
./mem-check.sh

# Run and auto-fix bloated apps
./mem-check.sh --fix
```

## What It Checks

| Check | What | Thresholds |
|-------|------|-----------|
| Memory pressure | % of RAM in use | Warning at 80% |
| Swap usage | GB of swap consumed | Warning at 10 GB, critical at 30 GB |
| Compressed memory | GB held by macOS compressor | Warning at 15 GB |
| Process memory | Per-process RSS | Flags apps over 1500 MB |
| Swap files | Count and disk usage of /var/vm/ | Informational |

## Auto-Fix Behavior (`--fix`)

When `--fix` is passed, the script will:

- **Restart** safe apps that are bloated (Finder, Ghostty, Terminal, iTerm2)
- **Send a notification** for apps it won't kill (Chrome, Slack, Spotify, Notion, Discord)
- **Never touch** system processes, IDE processes, or anything not in the safe lists

Edit the `RESTARTABLE_APPS` and `NOTIFY_ONLY_APPS` arrays in `mem-check.sh` to customize.

## Automated Scheduling

Install a launchd job that runs every 10 minutes:

```bash
# Monitor only (default: every 10 min)
./install.sh

# Monitor + auto-fix, every 5 minutes
./install.sh --interval 5 --fix

# Remove the scheduled job
./install.sh --uninstall
```

### Managing the Schedule

```bash
# Check if it's running
launchctl print gui/$(id -u)/com.gj.mem-check

# View logs
ls ~/.local/logs/mem-check/
cat ~/.local/logs/mem-check/$(date +%Y-%m-%d).log

# Temporarily stop
launchctl bootout gui/$(id -u)/com.gj.mem-check

# Re-enable
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.gj.mem-check.plist
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Healthy |
| 1 | Warning (elevated swap) |
| 2 | Critical (swap thrashing or high pressure) |

Useful for chaining: `./mem-check.sh --quiet || notify-send "Memory warning"`

## Tuning Thresholds

Edit the config section at the top of `mem-check.sh`:

```bash
SWAP_WARN_GB=10       # When to start worrying about swap
SWAP_CRIT_GB=30       # When swap is dangerously high
APP_WARN_MB=1500      # Flag individual apps above this
PRESSURE_WARN_PCT=80  # Memory pressure warning threshold
```

## Your System Context

Based on your setup (64 GB RAM, macOS Sonoma):

- **Ghostty** regularly balloons to 2+ GB — likely scrollback buffers from long-running processes. Add `scrollback-limit = 10000` to your Ghostty config.
- **Finder** at 2+ GB is abnormal — usually caused by network drives, large Quick Look caches, or too many Finder windows. Restarting Finder is always safe.
- **Chrome** — use a tab suspender extension. Each tab is a separate process.
- **44 GB swap** with 64 GB RAM means total memory demand was ~100+ GB — no amount of RAM would prevent this without closing apps.

## Log Rotation

Logs are stored per-day in `~/.local/logs/mem-check/`. To auto-clean old logs:

```bash
# Add to crontab: delete logs older than 30 days
0 0 * * * find ~/.local/logs/mem-check -name "*.log" -mtime +30 -delete
```
