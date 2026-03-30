# DevPulse

The only Mac performance tool that understands your dev workflow.

DevPulse lives in your menu bar and tells you what's actually eating your RAM — per-project, per-app, with one-click actions. It knows the difference between Chrome's 59 helper processes and your IDE, detects zombie processes, catches Docker waste, and answers the question every developer asks: **"Do I need a new Mac?"**

## Features

**Memory Intelligence**
- Real-time memory, swap, and compression tracking
- Per-project process grouping (node processes attributed to the project that spawned them)
- App family aggregation (Chrome's 59 processes → one line showing 22.5 GB)
- Expandable breakdowns with subprocess types and memory per type

**Chrome & Docker Awareness**
- Chrome tab count, renderer/extension memory split, avg MB per tab
- One-click Chrome Task Manager and Memory Saver access
- Docker VM reservation vs actual container usage
- Idle Docker detection (VM running, no containers)

**Zombie Hunter**
- Detects orphaned dev processes (node, tsserver, LSPs, build tools)
- Per-project zombie grouping with one-click kill
- Background auto-optimizer kills zombies automatically every 5 minutes

**"Do I Need a New Mac?"**
- Tracks peak memory over 7 rolling days
- Calculates waste: zombies + Docker overhead + Electron duplicates + idle dev servers
- Gives a straight verdict: "Absolutely not." / "Not yet — clean up first." / "Yeah, probably."
- Names specific culprits and suggests concrete actions

**"Can I Run?" Local AI Models**
- 20+ models: Llama 3, Qwen 2.5, DeepSeek R1, Mistral, Gemma, Phi-4, CodeLlama
- Shows feasibility per model based on your actual RAM usage
- Factors in recoverable waste: "After cleanup, you could run Llama 3 70B Q4"
- Links to Ollama and LM Studio

**Auto-Optimizer Agent**
- Background agent runs every 5 minutes
- Auto-kills zombie processes, notifies about idle servers, warns about Chrome leaks
- Tracks impact: zombies killed, memory freed, warnings sent
- Toggle on/off from the popover

**RAM Report**
- Full report panel via Cmd+Shift+M
- System overview, verdict, waste breakdown, top processes, AI model compatibility
- Weekly summary notification

## Install

```bash
# Build and install
git clone https://github.com/user/devpulse.git
cd devpulse
bash build.sh
```

Or with Homebrew (coming soon):
```bash
brew tap user/devpulse
brew install --cask devpulse
```

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon or Intel

## How It Works

DevPulse is a native Swift app that runs in your menu bar. It uses:
- Darwin APIs for memory stats (no shell commands for core metrics)
- `ps` for process discovery and attribution
- AppleScript for Chrome tab counting and graceful quit
- `docker stats` for container memory
- Local JSON storage for 7-day tracking (~30 KB)
- macOS notifications for alerts

**Footprint:** <30 MB RAM, <0.5% CPU.

## Development

```bash
# Build and install (dev mode, ad-hoc signing)
bash build.sh

# Release build (with Developer ID)
DEVELOPER_ID="Developer ID Application: ..." bash scripts/release.sh
```

Project structure:
```
DevPulse.app/Sources/
  DevPulseApp.swift    — App entry, status bar, popover, actions
  PopoverView.swift    — SwiftUI popover UI
  AppState.swift       — Observable state model
  MemoryStats.swift    — System memory via Darwin APIs
  TopProcesses.swift   — Process detection, grouping, Docker, Chrome, zombies
  RAMAdvisor.swift     — 7-day tracking, verdicts, "Can I Run?" model database
  AutoOptimizer.swift  — Background optimization agent
```

## License

MIT
