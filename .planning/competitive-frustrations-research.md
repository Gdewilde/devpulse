# Competitive Frustrations Research: What Developers Hate About Existing Tools

*Research compiled March 2026 from Hacker News, forums, GitHub issues, and review sites.*

---

## 1. iStat Menus

### Core Complaints

**Bloat and resource consumption.** iStat Menus itself is a resource hog. One reviewer reported the app consuming **1,997 MB of RAM** — nearly 2 GB — describing it as "eating up the memory." A Hacker News commenter noted that Stats (the open-source alternative) was described as "10x lighter than iStat Menus." Another user called it outright: **"Impossible to 'Quit' the app. Impossible to uninstall cleanly. BLOATWARE."**

**Version 7 regression.** Users upgrading from v6 to v7 report it is "incredibly buggy" — settings don't propagate to other screens, graphs show old data, colors don't update. One user said: **"Give us back the iStat Menus 6. There were so much clearer and better!"** Import/export of settings (critical for multi-machine dev setups) still wasn't working months after launch.

**Missing developer-relevant features.** Users specifically called out missing GPU memory display and lack of system memory history graphs. No awareness of what *processes* are causing spikes — just raw numbers with no developer context.

**Apple Silicon lag.** One reviewer noted it "still not fully support M5 chip" — a recurring pattern of slow adaptation to new Apple hardware.

**Pricing friction.** "Having 1 activation per license is usually fine, having to pay for upgrades kinda sucks." Developers managing multiple machines find per-seat licensing painful.

### DevPulse Opportunity
iStat Menus shows everything but understands nothing. It has no concept of "this memory spike is Xcode indexing" or "Docker is eating your swap." It's a dashboard, not an advisor.

---

## 2. CleanMyMac X

### Core Complaints

**Generic cleanup vs. developer-aware cleanup.** CleanMyMac is described as "bloated, expensive, trust issues" by the developer community. It treats all caches equally — it doesn't know that deleting Xcode DerivedData will cause a 20-minute rebuild, or that nuking `node_modules` in an active project means running `npm install` again.

**Trust deficit.** Developers don't trust it with their files. The tool shows no risk levels for what it's about to delete. Compare this to ClearDisk (an open-source competitor) which explicitly shows **"Safe/Caution/Risky"** labels for each cache type. CleanMyMac just shows a big "Clean" button.

**Subscription model backlash.** From HN: **"Part of the backlash against subscription is the lack of transparency. Store pages never mention the cost."** Developers resent paying recurring fees for what they see as a glorified `rm -rf` command.

**Doesn't understand dev artifacts.** CleanMyMac's "Xcode Junk" cleaner exists but is a bolt-on feature, not a core design principle. It doesn't know about: Homebrew caches, Cargo target directories, Go module caches, pip virtualenvs, Gradle caches, CocoaPods, SPM build folders, or Ollama model files.

### DevPulse Opportunity
The gap is enormous: CleanMyMac is built for consumers who download too many photos. DevPulse can be the tool that says "You have 47 GB of stale DerivedData from projects you haven't touched in 6 months — safe to clean."

---

## 3. Activity Monitor (built-in)

### Core Complaints

**Misleading on Apple Silicon.** AppleInsider reported: Activity Monitor energy usage figures are **"not just useless, but actually misleading"** on Apple Silicon because of confounding by core type and frequency. Apple has not updated Activity Monitor to account for this in the entire Apple Silicon era.

**No developer context.** Activity Monitor shows raw process lists with no grouping, no understanding that 12 `node` processes belong to one webpack build, no awareness that `mds_stores` is Spotlight indexing your `node_modules`. As one developer put it: **"My ~/Library directory is currently 47G(!!) and it's mostly a bunch of shit that I have no idea whether I need or not."**

**No historical data.** You can see what's happening *now* but not what happened 10 minutes ago when your fan went berserk. No timeline, no session tracking, no "what changed."

**Can't handle zombie processes intelligently.** Activity Monitor shows zombie processes with a "Z" status but provides no way to deal with them. You can't kill a zombie (it's already dead) — you need to kill its parent. Activity Monitor doesn't surface parent-child relationships in an actionable way. If the parent is `launchd`, your only option is to reboot.

**No GPU VRAM visibility.** For developers running local LLMs or ML workloads, Activity Monitor provides zero visibility into GPU memory allocation, unified memory pressure from Metal workloads, or model loading status.

### DevPulse Opportunity
Activity Monitor is stuck in 2010. It was designed for "why is my Mac slow" consumer troubleshooting, not "why did my Xcode build just use 14 GB of RAM and can I prevent that."

---

## 4. Stats (Open Source Menu Bar Monitor)

### Core Complaints

**CPU overhead.** Hacker News users report **"Stats would use quite a bit more CPU usage compared to iStat Menus"** — ironic for a monitoring tool. The Sensors and Bluetooth modules are particularly expensive, with disabling them potentially reducing CPU usage by up to 50%.

**Poor initial UX.** The app shows only battery initially because other modules are hidden. New users have no indication that more monitoring items exist — a discoverability failure.

**Text rendering issues.** "The text in the menu bar is too thin for my eyes, and the developer wasn't receptive to my PR." The maintainer rejected accessibility improvements.

**Sensor naming is misleading.** The README itself admits: "CPU Efficient Core 1" does not represent the temperature of a single efficient core — it's just one thermal zone. Developers looking for accurate per-core data are misled.

**No actionable intelligence.** Like iStat Menus, Stats shows numbers but doesn't interpret them. It doesn't know why your memory is full or what you can do about it.

### DevPulse Opportunity
Stats is "iStat Menus but free" — which means it inherits all of iStat's conceptual limitations (raw metrics, no developer context) while also being rougher around the edges.

---

## 5. Raycast

### Core Complaints

**System monitoring is a bolted-on extension, not core.** Raycast's system monitor is a community extension, not built-in. It shows basic CPU/Memory/Disk/Battery but requires invoking a command — there's no persistent, glanceable menu bar presence.

**No continuous monitoring.** Raycast is a launcher — you invoke it, do something, and dismiss it. This interaction model is fundamentally wrong for system monitoring, which needs to be ambient and always-visible. You can't glance at Raycast to see if Docker is eating your RAM.

**Focused on productivity, not system health.** Raycast excels at searching npm packages, managing GitHub repos, and creating Jira tickets. But it has zero awareness of: memory pressure trends, disk space warnings, process health, GPU utilization, or container resource usage.

### DevPulse Opportunity
Raycast is the "do things" tool. DevPulse is the "know things" tool. They're complementary, not competitive — but Raycast users currently have a blind spot for system health.

---

## 6. LM Studio / Ollama

### Core Complaints

**The 75% VRAM cap nobody explains.** Apple Silicon limits GPU access to ~66-75% of unified memory (66% for <=36GB, 75% for >36GB). This is invisible to users. Apple calls it "unified memory" in marketing but silently caps GPU usage. Some call this **"false advertising"** — and neither Ollama nor LM Studio surface this constraint clearly.

**Silent memory offloading.** macOS can silently offload a model from fast VRAM back to system RAM. When you next query the model, there's a multi-second delay while it shuffles back. No tool warns you this is happening or why.

**KV cache memory explosion.** Increasing context length from 2048 to 8192 tokens **4x the KV cache memory**. Neither tool warns you before this causes GPU memory to overflow to CPU, tanking performance.

**Ollama has no visual resource monitor.** Ollama outputs VRAM info only to log files. You need `ollama ps` in a terminal to check what's loaded. There's no dashboard, no warnings, no "you're about to exceed VRAM" alerts.

**LM Studio's monitor is isolated.** LM Studio has an inline VRAM gauge, but it only knows about its own usage — not system-wide GPU memory pressure from other apps.

### DevPulse Opportunity
This is a greenfield opportunity. No existing menu bar tool shows: current VRAM usage by Ollama models, remaining VRAM headroom, warnings when a model load will exceed GPU memory, or alerts when macOS silently offloads to CPU.

---

## 7. Docker Desktop Resource Panel

### Core Complaints

**Per-container limits, not global limits.** The most damning quote from Docker forums: **"What I really need is a global limit for all 5 containers and then just let them fight for what is available."** Docker Desktop applies memory limits per-container, not as a system-wide ceiling. Set 1GB limit with 5 containers = 5GB total, not 1GB shared.

**Memory consumption despite limits.** "Sometimes all 8gb of ram are consumed and the system becomes unresponsive and sometimes docker desktop crashes." CPU limits similarly ineffective: "I have seen the same behavior when I limit the CPUs. All 4 CPUs still get pegged."

**No host system awareness.** Docker's resource panel shows container metrics in isolation. It doesn't show "Docker is using 60% of your system's RAM, leaving your IDE starved." Developers want to **"reserve some amount to keep the host alive and available for other small tasks."**

**15GB idle memory consumption.** A GitHub issue documents Docker Desktop consuming ~15GB RAM with zero containers running, worsening over time. Background services (Kubernetes, Docker Scout, VS Code integration) silently consume 1-2GB each.

**Zombie container processes.** Docker for Mac has documented issues with zombie processes that aren't reaped after normal container exit and prevent Docker from restarting.

### DevPulse Opportunity
DevPulse can be the "Docker impact on your system" view that Docker Desktop itself refuses to provide — showing total Docker memory footprint alongside everything else competing for resources.

---

## 8. htop / btop

### Core Complaints

**macOS is a second-class citizen.** htop has persistent macOS compatibility issues. btop installation on macOS requires Xcode, MacPorts, and font configuration — a frustrating bootstrapping problem for a monitoring tool.

**Missing features on macOS.** btop is missing: recursive tree view close, per-process CPU time, showing threads as separate items, and showing recently dead processes — all features htop has on Linux.

**Terminal-only, no ambient awareness.** Both tools require an open terminal window. You can't glance at your menu bar during a compile to see resource usage. They compete for screen real estate with the very terminal work you're trying to monitor.

**No developer-semantic grouping.** htop shows 47 `node` processes individually. It doesn't group them as "webpack dev server" or "Next.js build." It doesn't know that `ruby` + `postgres` + `redis` = "your Rails stack."

**PATH issues on macOS.** MacPorts doesn't add itself to `$PATH` by default, causing confusion during installation.

### DevPulse Opportunity
htop/btop are powerful but require active attention in a terminal. DevPulse provides ambient, glanceable monitoring that coexists with your actual work.

---

## 9. CleanMyMac vs. Developer-Aware Cleanup

### The Core Gap

From Hacker News, the creator of Room Service articulated the problem perfectly: **"macOS groups a lot of this into 'System Data', which isn't very actionable."** And: **"The harder problem turned out to be understanding what's actually taking space."**

**What generic cleaners miss entirely:**
- Xcode DerivedData: can grow to **80+ GB**
- node_modules across projects: easily **tens of GB**
- Docker images/volumes: **50-200 GB** for active developers
- Homebrew caches: grows with every `brew install`
- Ollama/HuggingFace model files: **"grow silently and are spread across different locations"**
- Cargo `target/` directories, Go module caches, pip virtualenvs
- Old iOS simulators, device support files

**The developer sentiment:** "Apple ruining your disk with Xcode, making *another* developer write the solution for it." Developers feel abandoned by both Apple (whose tools create the bloat) and generic cleaners (who don't understand it).

**Skepticism toward paid tools.** Many developers respond to cleanup tools with "I can write a bash script for this." The counter-opportunity is: yes, but you won't. And a script doesn't give you proactive warnings or safe/risky classifications.

### DevPulse Opportunity
The winning angle is not just "clean stuff" but "understand what's safe to clean, warn before it's a problem, and know the difference between a stale cache and an active build artifact."

---

## 10. DaisyDisk

### Core Complaints

**Beautiful but developer-ignorant.** DaisyDisk shows a stunning sunburst visualization of disk usage, but it treats `node_modules` the same as your Photos library. It can't tell you "this is a stale project you haven't built in 3 months" vs. "this is your active production app."

**No project-type awareness.** DaisyDisk doesn't recognize: Node.js projects (node_modules), Rust projects (target/), Swift projects (DerivedData), Go projects (vendor/), or any other development artifact patterns.

**Manual identification burden.** You have to visually scan the sunburst, click into directories, and manually determine what's safe to delete. For a developer with 50+ projects, this is hours of work.

**No recurring monitoring.** DaisyDisk is a point-in-time scan. It doesn't warn you when a project's build artifacts cross a threshold or when your total dev cache exceeds a limit.

### DevPulse Opportunity
DaisyDisk answers "what's big?" DevPulse can answer "what's big, stale, and safe to remove?"

---

## Meta-Pattern: The Developer-Awareness Gap

Across all 10 tools, one theme emerges consistently:

> **"I wish this tool understood that I'm a developer."**

Specifically, developers want tools that know:

1. **What processes mean together** — not 47 individual `node` PIDs, but "webpack build consuming 4.2 GB"
2. **What's safe to delete** — DerivedData from 6 months ago is safe; DerivedData from your current branch is not
3. **What's coming** — "Ollama is about to load a 13B model that will exceed your VRAM" before it happens
4. **What caused the problem** — not just "memory is at 95%" but "Docker containers grew 3GB in the last hour"
5. **Developer-specific resource consumers** — Xcode indexing, Spotlight scanning node_modules, Docker's hidden overhead, Homebrew's cache accumulation
6. **Session context** — what changed between "my Mac was fast this morning" and "my Mac is crawling now"
7. **Unified visibility** — Docker + Ollama + Xcode + Node all competing for the same RAM/VRAM, visible in one place

No existing tool delivers on more than 1-2 of these. That's the gap DevPulse can own.

---

## Sources

- [iStat Menus Customer Reviews - Setapp](https://setapp.com/apps/istat-menus/customer-reviews)
- [iStat Menus 7 Redesign Discussion - MacRumors Forums](https://forums.macrumors.com/threads/istat-menus-7-0-brings-comprehensive-redesign-and-new-features.2432615/page-7)
- [Stats macOS System Monitor - Hacker News](https://news.ycombinator.com/item?id=42881342)
- [Stats GitHub Repository](https://github.com/exelban/stats)
- [Show HN: macOS App for Dev Machine Cleanup](https://news.ycombinator.com/item?id=40382941)
- [Show HN: Clean Your Mac with a Script](https://news.ycombinator.com/item?id=42250429)
- [Room Service: Understand What's Filling Your Mac - Hacker News](https://news.ycombinator.com/item?id=47523979)
- [Activity Monitor Wrong About Energy on Apple Silicon - AppleInsider](https://appleinsider.com/articles/22/05/03/activity-monitor-in-macos-is-wrong-about-energy-usage-of-apple-silicon)
- [Apple Silicon LLM Limitations](https://stencel.io/posts/apple-silicon-limitations-with-usage-on-local-llm%20.html)
- [Docker Desktop Memory Issues - Docker Forums](https://forums.docker.com/t/docker-desktop-eats-memory-despite-limit/139981)
- [Docker Desktop Idle Memory - Docker Forums](https://forums.docker.com/t/docker-desktop-idle-memory-usage/138540)
- [Docker for Mac Zombie Processes - GitHub](https://github.com/docker/for-mac/issues/6451)
- [Docker Desktop 15GB Memory Usage - GitHub](https://github.com/docker/for-win/issues/13433)
- [ClearDisk - Developer Cache Cleaner](https://github.com/bysiber/cleardisk)
- [DevCleaner for Xcode](https://parthvatalia.medium.com/devcleaner-the-one-click-solution-that-freed-up-80gb-on-my-mac-3598bb540863)
- [Ollama VRAM Not Fully Utilized - GitHub](https://github.com/ollama/ollama/issues/7629)
- [LM Studio Excessive RAM Allocation - GitHub](https://github.com/lmstudio-ai/lmstudio-bug-tracker/issues/1198)
- [How to Free Disk Space on Dev MacBook](https://pawelurbanek.com/macos-free-disk-space)
- [Raycast System Monitor Extension](https://www.raycast.com/hossammourad/raycast-system-monitor)
- [Mole - Mac Deep Clean Tool](https://github.com/tw93/mole)
- [iStat Menu Alternatives - MacRumors](https://forums.macrumors.com/threads/istat-menu-alternative.2253977/)
