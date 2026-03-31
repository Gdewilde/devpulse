# DevPulse

The only Mac performance tool that understands your dev workflow.

DevPulse lives in your menu bar and tells you what's actually eating your RAM — per-project, per-app, with one-click actions. It knows the difference between Chrome's 59 helper processes and your IDE, detects zombie processes, catches Docker waste, and answers the question every developer asks: **"Do I need a new Mac?"**

## Features

**Memory Intelligence**
- Real-time memory, swap, and compression tracking
- Per-project process grouping (node processes attributed to the project that spawned them)
- App family aggregation (Chrome's 59 processes → one line showing 22.5 GB)
- Expandable breakdowns with subprocess types and memory per type
- Swap velocity tracking with thrashing prediction

**GPU / VRAM Monitoring**
- Real-time GPU memory tracking via Metal + IOKit (system-wide)
- Shows GPU allocated and available headroom for local AI models
- Unified memory awareness for Apple Silicon

**Chrome & Docker Awareness**
- Chrome tab count, renderer/extension memory split, avg MB per tab
- One-click Chrome Task Manager and Memory Saver access
- Docker VM reservation vs actual container usage
- Idle Docker detection (VM running, no containers)

**Zombie Hunter**
- Detects orphaned dev processes (node, tsserver, LSPs, build tools)
- Stale LSP and file watcher detection
- Per-project zombie grouping with one-click kill
- Background auto-optimizer kills zombies automatically every 5 minutes
- Desktop notifications for new zombie detections

**"Do I Need a New Mac?"**
- Tracks peak memory over 7 rolling days
- Calculates waste: zombies + Docker overhead + Electron duplicates + idle dev servers
- Gives a straight verdict: "Absolutely not." / "Not yet — clean up first." / "Yeah, probably."
- Names specific culprits and suggests concrete actions

**"Can I Run?" Local AI Models**
- 20+ models: Llama 3/4, Qwen 2.5, DeepSeek R1, Mistral, Gemma, Phi-4, CodeLlama
- Shows feasibility per model based on your actual RAM and GPU usage
- Factors in recoverable waste: "After cleanup, you could run Llama 3 70B Q4"
- Click any model for Ollama links, `ollama pull` clipboard copy, and detail pages

**Session Profiles**
- Auto-detects your current workspace (Frontend, Backend, Full Stack, etc.)
- One-click profile switching — quits unneeded apps, launches missing ones
- Learning mode: observes your app patterns and suggests new profiles
- Custom profile creation and editing in Settings

**Smart Cleanups**
- Quick Clean: one-click cleanup of zombies, Docker waste, and idle servers
- Before/after feedback showing memory freed
- SSD health monitoring (data written, lifetime tracking)

**Auto-Optimizer Agent**
- Background agent runs every 5 minutes
- Auto-kills zombie processes, notifies about idle servers, warns about Chrome leaks
- Tracks impact: zombies killed, memory freed, warnings sent
- Toggle on/off from the popover

**RAM Report & Timeline**
- Full report panel via Cmd+Shift+M
- System overview, GPU stats, verdict, waste breakdown, top processes, AI model compatibility
- Memory timeline with event detection (spikes, Docker starts, etc.)
- Weekly summary notification

**Auto-Update**
- Checks GitHub releases on launch
- Shows update badge in footer when a new version is available

## Install

Download the latest DMG from [Releases](https://github.com/Gdewilde/devpulse/releases), open it, and drag DevPulse to Applications.

Or build from source:
```bash
git clone https://github.com/Gdewilde/devpulse.git
cd devpulse
bash build.sh
```

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon or Intel

## How It Works

DevPulse is a native Swift app that runs in your menu bar. It uses:
- Darwin APIs for memory stats (no shell commands for core metrics)
- Metal + IOKit for GPU/VRAM monitoring
- `ps` for process discovery and attribution
- AppleScript for Chrome tab counting and graceful quit
- `docker stats` for container memory
- GitHub API for update checks
- Local JSON storage for 7-day tracking (~30 KB)
- macOS notifications for alerts

**Footprint:** <30 MB RAM, <0.5% CPU.

## Development

```bash
# Build and install (dev mode, ad-hoc signing)
bash build.sh

# Release build (with Developer ID)
DEVELOPER_ID="Developer ID Application: ..." bash release.sh
```

Project structure:
```
DevPulse/Sources/
  DevPulseApp.swift        — App entry, status bar, popover, actions, update checker
  PopoverView.swift        — SwiftUI popover UI
  AppState.swift           — Observable state model
  MemoryStats.swift        — System memory via Darwin APIs, GPU via Metal/IOKit, SSD health
  TopProcesses.swift       — Process detection, grouping, Docker, Chrome, zombies
  RAMAdvisor.swift         — 7-day tracking, verdicts, "Can I Run?" model database
  AutoOptimizer.swift      — Background optimization agent
  CleanupActions.swift     — Quick Clean and smart cleanup actions
  SessionProfiles.swift    — Session profile detection, switching, learning
  Preferences.swift        — App preferences and settings storage
  ProfileSettingsView.swift — Settings panel UI
  TimelineStore.swift      — Memory timeline recording and event detection
```

## License

[Business Source License 1.1](https://mariadb.com/bsl11/) (BUSL-1.1). After the change date, the work is available under [MPL 2.0](https://www.mozilla.org/MPL/2.0/). See `LICENSE` for the full terms and parameters.
