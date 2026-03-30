# DevPulse — Mac Performance Manager for Developers

## Vision

The only Mac performance tool that understands your development workflow.
It knows which project is eating your RAM, why, and how to fix it.

## Target Audience

Developers running heavy workloads on Mac: multiple IDE workspaces, Electron apps (Slack, Notion, Discord), Docker containers, AI tools (Claude Code, Copilot), and dev servers. Typically 16-64 GB RAM, still swapping.

## Pricing Model

- **Free:** Menu bar monitor + per-project memory view + quit/force quit
- **Pro ($12 one-time):** Smart alerts, cleanup actions, RAM advisor, timeline, zombie detection

## Competitive Edge

| Feature | Activity Monitor | iStat Menus | Stats (free) | DevPulse |
|---------|-----------------|-------------|-------------|----------|
| Per-project memory | - | - | - | Yes |
| Developer-aware grouping | - | - | - | Yes |
| "Do you need more RAM?" | - | - | - | Yes |
| "Can I run this AI model?" | - | - | - | Yes |
| Zombie process detection | - | - | - | Yes |
| Docker memory waste | - | - | - | Yes |
| Dev cache cleanup | - | - | - | Yes |
| Spotlight index fixer | - | - | - | Yes |

---

## Roadmap

### Phase 1: Foundation (current state -> v1.0)

Rename, rebrand, polish what exists into a shippable free product.

- [ ] Rename to DevPulse throughout (binary, bundle ID, plist, menus)
- [ ] New app icon (chip/pulse motif)
- [ ] Fix dark mode polish (current colors verified working)
- [ ] Expand project attribution — show breakdown inside each group
      "unify: 11.2 GB — 8 node, 2 LSPs, 1 Cursor workspace"
- [ ] Process kill actions (Quit / Force Quit from submenu) — done
- [ ] Build pipeline: build.sh auto-installs + relaunches — done
- [ ] Landing page (one-pager explaining the value prop)
- [ ] Ship free version on GitHub + Homebrew cask

### Phase 2: Zombie Hunter (v1.1)

The first feature nobody else has. Make it immediately useful.

- [ ] Detect orphaned node processes (parent exited, still running)
- [ ] Detect stale LSP servers for projects no longer open in any IDE
- [ ] Detect stale file watchers (fswatch, chokidar, esbuild)
- [ ] "Zombies" section in menu with one-click "Kill All Zombies"
- [ ] Notification when zombies detected: "3 orphaned processes using 1.2 GB"
- [ ] Track which project spawned them (via args path attribution)

### Phase 3: RAM Advisor (v1.2)

"Do you need to buy a new Mac, or just optimize?"

This is the headline feature. Analyze usage patterns and give a verdict.

- [x] Track peak memory over rolling 7 days
- [x] Calculate "optimized memory" = peak minus waste:
      - Zombie processes (recoverable) ✓
      - Docker VM overhead vs actual container usage (recoverable) ✓
      - Duplicate Electron runtimes across apps (not recoverable but educatable) ✓
      - Inactive project dev servers still running (recoverable) ✓
      - DerivedData / build caches detection ✓
- [x] Verdict engine with context-aware messages:
      - Identifies biggest waste source and suggests specific action
      - Four rating tiers: plenty, fine, tight, needs more
      - Waste breakdown by source (zombies, Docker, Electron, idle servers)
- [x] Show this as a dedicated "RAM Report" panel (Cmd+Shift+M hotkey)
- [x] Weekly summary notification: "This week: peak 54 GB, 12 GB recoverable waste"
- [x] "Can I Run?" local AI model checker (inspired by https://www.canirun.ai/)
      - 20+ models: Llama, Qwen, Mistral, DeepSeek, Gemma, Phi, CodeLlama, etc.
      - Shows feasibility: runs great / runs OK / after cleanup / too heavy
      - Suggests best quantization level per model
      - Links to Ollama and LM Studio for setup
      - Full model list in "See All Models" submenu

### Phase 4: Smart Cleanups (v1.3)

One-click actions that save real memory.

- [ ] Kill zombie processes (from Phase 2)
- [ ] Restart Docker Desktop VM (reclaims hoarded memory)
- [ ] Clear Xcode DerivedData (with age filter: only projects not built in 30+ days)
- [ ] Add .metadata_never_index to all node_modules (stops Spotlight CPU spikes)
- [ ] Exclude build dirs from Spotlight (target/, .build/, dist/, .next/)
- [ ] Purge Docker build cache (show size first, confirm)
- [ ] "Quick Clean" button: runs all safe cleanups in sequence, reports savings
- [ ] Before/after memory comparison: "Freed 4.2 GB"

### Phase 5: Docker Awareness (v1.4)

Docker Desktop is the #2 developer memory complaint after Electron.

- [x] Detect Docker Desktop running + VM memory reservation
- [x] Query `docker stats` for actual per-container memory
- [x] Show waste: "Docker VM: 6.2 GB reserved, containers using 1.8 GB (4.4 GB wasted)"
- [x] Detect idle Docker (no containers running but VM still up)
- [ ] "Restart Docker VM" action (reclaims memory, containers restart)
- [ ] Surface OrbStack as alternative when waste is chronic
- [ ] Support Apple Containers (macOS 26) when available

### Phase 6: Memory Timeline (v1.5)

Answer "what happened at 3pm that killed my Mac?"

- [ ] Log memory snapshots every 60 seconds to local SQLite
- [ ] Auto-annotate events:
      - App launch/quit (detect via NSWorkspace notifications)
      - Build started (detect Xcode, webpack, esbuild, cargo spikes)
      - Docker compose up/down
      - Swap threshold crossings
- [ ] Timeline view (floating panel or menu bar detail view)
- [ ] "Last 24 hours" and "Last 7 days" views
- [ ] Tap any point to see process breakdown at that moment
- [ ] Export as shareable image (for bug reports / team discussions)

### Phase 7: Swap Velocity + SSD Health (v1.6)

Address the SSD anxiety that developers have.

- [ ] Track swap growth rate: "Swap growing at 2 GB/hr"
- [ ] Predict time to thrashing: "At this rate, thrashing in ~3 hours"
- [ ] Read SMART data for SSD lifetime: "45 TB written / 150 TB rated (30%)"
- [ ] Weekly SSD wear report
- [ ] Alert when swap velocity is dangerous (before thrashing starts)

### Phase 8: Dev Session Profiles (v2.0)

One-click workspace switching.

- [ ] Define profiles: "Frontend" (Cursor + Chrome + Figma), "Backend" (Cursor + Docker + Postgres), "Light" (browser only)
- [ ] Switch profiles: gracefully quit apps not in target profile, launch missing ones
- [ ] Auto-detect current profile based on running apps
- [ ] Estimated memory for each profile
- [ ] Schedule: "Switch to Light at 6pm" (end of workday)

---

## Technical Decisions

**Language:** Swift (native, low footprint, menu bar first-class)
**Data storage:** SQLite for timeline data, UserDefaults for preferences
**Distribution:** GitHub releases + Homebrew cask (free), Gumroad or Paddle (Pro)
**Footprint target:** <30 MB RAM, <0.5% CPU
**Min OS:** macOS 14 (Sonoma)
**Sandboxing:** NOT on Mac App Store (needs full process access, Docker socket, SMART data)

## Revenue Milestones

| Milestone | Target |
|-----------|--------|
| GitHub stars | 500 in first month |
| Free users | 5,000 in 3 months |
| Pro conversions | 5% = 250 paid ($3,000) |
| Steady state (12 mo) | 2,000 Pro users ($24,000/yr) |
| Stretch (24 mo) | 10,000 Pro ($120,000/yr) |

## Name Rationale

"DevPulse" — pulse = heartbeat monitoring, dev = developer-first. Short, memorable, available as a domain. Alternatives considered: DevMeter, CodePulse, MacPulse, Heartbeat.
