import Foundation

// MARK: - App Alternatives Engine
// Recommends lighter alternatives for memory-hungry apps detected in the process list.
// Each alternative includes typical RAM savings, tradeoffs, and a difficulty rating.

struct AppAlternative: Identifiable {
    let id: String           // unique key
    let name: String         // e.g. "Zed"
    let typicalMB: Int       // typical RAM usage
    let savingsMB: Int       // estimated savings vs the offender
    let difficulty: Difficulty
    let tradeoff: String     // what you give up
    let url: String?         // download/info URL
    let websiteSlug: String? // for devpulse.sh/apps/<slug>

    enum Difficulty: String {
        case easy = "Easy"       // drop-in replacement
        case medium = "Medium"   // some adjustment needed
        case hard = "Hard"       // different paradigm
    }
}

struct AppOffender {
    let processNames: [String]     // process names to match (e.g. ["Google Chrome", "Chrome"])
    let displayName: String        // human-readable name
    let category: String           // "Browser", "Editor", etc.
    let typicalMB: Int             // typical RAM for this app
    let icon: String               // SF Symbol
    let alternatives: [AppAlternative]
    let websiteSlug: String?       // for devpulse.sh/apps/<slug>
}

/// Database of known memory-hungry apps and their lighter alternatives.
let appAlternativesDatabase: [AppOffender] = [

    // MARK: - Browsers

    AppOffender(
        processNames: ["Google Chrome", "Chrome", "Google Chrome Helper"],
        displayName: "Google Chrome",
        category: "Browser",
        typicalMB: 1000,
        icon: "globe",
        alternatives: [
            AppAlternative(id: "safari", name: "Safari", typicalMB: 400, savingsMB: 600,
                difficulty: .easy, tradeoff: "Fewer extensions, less DevTools polish",
                url: nil, websiteSlug: "safari"),
            AppAlternative(id: "brave", name: "Brave", typicalMB: 600, savingsMB: 400,
                difficulty: .easy, tradeoff: "Some site compatibility edge cases",
                url: "https://brave.com", websiteSlug: "brave"),
            AppAlternative(id: "orion", name: "Orion", typicalMB: 350, savingsMB: 650,
                difficulty: .easy, tradeoff: "Smaller community, occasional extension issues",
                url: "https://browser.kagi.com", websiteSlug: "orion"),
            AppAlternative(id: "firefox", name: "Firefox", typicalMB: 850, savingsMB: 150,
                difficulty: .easy, tradeoff: "Similar RAM, better privacy defaults",
                url: "https://firefox.com", websiteSlug: "firefox"),
        ],
        websiteSlug: "chrome"
    ),

    AppOffender(
        processNames: ["Arc", "Arc Helper"],
        displayName: "Arc",
        category: "Browser",
        typicalMB: 700,
        icon: "globe",
        alternatives: [
            AppAlternative(id: "safari-arc", name: "Safari", typicalMB: 400, savingsMB: 300,
                difficulty: .easy, tradeoff: "No spaces/easels, fewer extensions",
                url: nil, websiteSlug: "safari"),
            AppAlternative(id: "orion-arc", name: "Orion", typicalMB: 350, savingsMB: 350,
                difficulty: .easy, tradeoff: "No Arc-style spaces, smaller community",
                url: "https://browser.kagi.com", websiteSlug: "orion"),
        ],
        websiteSlug: "arc"
    ),

    // MARK: - Code Editors

    AppOffender(
        processNames: ["Electron", "Code Helper", "Code - Insiders Helper", "code", "Code Helper (Renderer)"],
        displayName: "VS Code",
        category: "Editor",
        typicalMB: 800,
        icon: "chevron.left.forwardslash.chevron.right",
        alternatives: [
            AppAlternative(id: "zed", name: "Zed", typicalMB: 180, savingsMB: 620,
                difficulty: .easy, tradeoff: "Maturing extension ecosystem, no remote SSH yet",
                url: "https://zed.dev", websiteSlug: "zed"),
            AppAlternative(id: "sublime", name: "Sublime Text", typicalMB: 80, savingsMB: 720,
                difficulty: .medium, tradeoff: "No built-in terminal, fewer IDE features",
                url: "https://sublimetext.com", websiteSlug: "sublime-text"),
            AppAlternative(id: "nova", name: "Nova", typicalMB: 250, savingsMB: 550,
                difficulty: .easy, tradeoff: "macOS-only, smaller plugin ecosystem",
                url: "https://nova.app", websiteSlug: "nova"),
            AppAlternative(id: "neovim", name: "Neovim", typicalMB: 50, savingsMB: 750,
                difficulty: .hard, tradeoff: "Steep learning curve, requires terminal comfort",
                url: "https://neovim.io", websiteSlug: "neovim"),
            AppAlternative(id: "helix", name: "Helix", typicalMB: 40, savingsMB: 760,
                difficulty: .hard, tradeoff: "Modal editing, no plugin system yet",
                url: "https://helix-editor.com", websiteSlug: "helix"),
        ],
        websiteSlug: "vscode"
    ),

    AppOffender(
        processNames: ["Cursor", "Cursor Helper", "Cursor Helper (Renderer)"],
        displayName: "Cursor",
        category: "Editor",
        typicalMB: 900,
        icon: "chevron.left.forwardslash.chevron.right",
        alternatives: [
            AppAlternative(id: "zed-cursor", name: "Zed", typicalMB: 180, savingsMB: 720,
                difficulty: .medium, tradeoff: "No inline AI chat (yet), smaller extension ecosystem",
                url: "https://zed.dev", websiteSlug: "zed"),
            AppAlternative(id: "vscode-cursor", name: "VS Code + Copilot", typicalMB: 800, savingsMB: 100,
                difficulty: .easy, tradeoff: "Less integrated AI, but lighter",
                url: "https://code.visualstudio.com", websiteSlug: "vscode"),
        ],
        websiteSlug: "cursor"
    ),

    AppOffender(
        processNames: ["idea", "webstorm", "pycharm", "goland", "clion", "rider", "rubymine", "phpstorm"],
        displayName: "JetBrains IDE",
        category: "Editor",
        typicalMB: 2000,
        icon: "chevron.left.forwardslash.chevron.right",
        alternatives: [
            AppAlternative(id: "fleet", name: "Fleet", typicalMB: 500, savingsMB: 1500,
                difficulty: .medium, tradeoff: "Still maturing, fewer refactoring tools",
                url: "https://www.jetbrains.com/fleet/", websiteSlug: "fleet"),
            AppAlternative(id: "vscode-jb", name: "VS Code", typicalMB: 800, savingsMB: 1200,
                difficulty: .medium, tradeoff: "Needs extensions for equivalent features",
                url: "https://code.visualstudio.com", websiteSlug: "vscode"),
            AppAlternative(id: "zed-jb", name: "Zed", typicalMB: 180, savingsMB: 1820,
                difficulty: .hard, tradeoff: "No deep refactoring, no built-in database tools",
                url: "https://zed.dev", websiteSlug: "zed"),
        ],
        websiteSlug: "jetbrains"
    ),

    // MARK: - Containers

    AppOffender(
        processNames: ["Docker", "com.docker.backend", "Docker Desktop", "com.docker.vmnetd"],
        displayName: "Docker Desktop",
        category: "Containers",
        typicalMB: 3000,
        icon: "shippingbox",
        alternatives: [
            AppAlternative(id: "orbstack", name: "OrbStack", typicalMB: 900, savingsMB: 2100,
                difficulty: .easy, tradeoff: "Paid after trial, full Docker CLI compatibility",
                url: "https://orbstack.dev", websiteSlug: "orbstack"),
            AppAlternative(id: "colima", name: "Colima", typicalMB: 400, savingsMB: 2600,
                difficulty: .medium, tradeoff: "CLI-only, no GUI dashboard",
                url: "https://github.com/abiosoft/colima", websiteSlug: "colima"),
            AppAlternative(id: "podman", name: "Podman", typicalMB: 500, savingsMB: 2500,
                difficulty: .medium, tradeoff: "Different CLI syntax for some commands",
                url: "https://podman.io", websiteSlug: "podman"),
        ],
        websiteSlug: "docker-desktop"
    ),

    // MARK: - Communication

    AppOffender(
        processNames: ["Slack", "Slack Helper", "Slack Helper (Renderer)"],
        displayName: "Slack",
        category: "Communication",
        typicalMB: 800,
        icon: "bubble.left.and.bubble.right",
        alternatives: [
            AppAlternative(id: "slack-web", name: "Slack (Safari)", typicalMB: 300, savingsMB: 500,
                difficulty: .easy, tradeoff: "No native notifications without Safari settings",
                url: "https://app.slack.com", websiteSlug: "slack-web"),
            AppAlternative(id: "ripcord-slack", name: "Ripcord", typicalMB: 40, savingsMB: 760,
                difficulty: .medium, tradeoff: "No threads, no huddles, no rich formatting",
                url: "https://cancel.fm/ripcord/", websiteSlug: "ripcord"),
        ],
        websiteSlug: "slack"
    ),

    AppOffender(
        processNames: ["Discord", "Discord Helper", "Discord Helper (Renderer)"],
        displayName: "Discord",
        category: "Communication",
        typicalMB: 500,
        icon: "bubble.left.and.bubble.right",
        alternatives: [
            AppAlternative(id: "discord-web", name: "Discord (Safari)", typicalMB: 250, savingsMB: 250,
                difficulty: .easy, tradeoff: "No push-to-talk hotkey, no overlay",
                url: "https://discord.com/app", websiteSlug: "discord-web"),
            AppAlternative(id: "ripcord-discord", name: "Ripcord", typicalMB: 40, savingsMB: 460,
                difficulty: .medium, tradeoff: "No rich embeds, limited formatting",
                url: "https://cancel.fm/ripcord/", websiteSlug: "ripcord"),
            AppAlternative(id: "legcord", name: "Legcord", typicalMB: 200, savingsMB: 300,
                difficulty: .easy, tradeoff: "Third-party client, occasional feature lag",
                url: "https://legcord.app", websiteSlug: "legcord"),
        ],
        websiteSlug: "discord"
    ),

    AppOffender(
        processNames: ["Microsoft Teams", "Teams", "Teams Helper"],
        displayName: "Microsoft Teams",
        category: "Communication",
        typicalMB: 1200,
        icon: "bubble.left.and.bubble.right",
        alternatives: [
            AppAlternative(id: "teams-web", name: "Teams (Safari)", typicalMB: 400, savingsMB: 800,
                difficulty: .easy, tradeoff: "Some call features limited in browser",
                url: "https://teams.microsoft.com", websiteSlug: "teams-web"),
        ],
        websiteSlug: "teams"
    ),

    AppOffender(
        processNames: ["zoom.us", "Zoom"],
        displayName: "Zoom",
        category: "Communication",
        typicalMB: 500,
        icon: "video",
        alternatives: [
            AppAlternative(id: "facetime", name: "FaceTime", typicalMB: 100, savingsMB: 400,
                difficulty: .easy, tradeoff: "Apple ecosystem only, no breakout rooms",
                url: nil, websiteSlug: "facetime"),
            AppAlternative(id: "zoom-web", name: "Zoom (Safari)", typicalMB: 300, savingsMB: 200,
                difficulty: .easy, tradeoff: "Some features require desktop app",
                url: nil, websiteSlug: "zoom-web"),
        ],
        websiteSlug: "zoom"
    ),

    // MARK: - Notes & Knowledge

    AppOffender(
        processNames: ["Notion", "Notion Helper"],
        displayName: "Notion",
        category: "Notes",
        typicalMB: 500,
        icon: "doc.text",
        alternatives: [
            AppAlternative(id: "obsidian", name: "Obsidian", typicalMB: 200, savingsMB: 300,
                difficulty: .medium, tradeoff: "No real-time collab, no databases (use Dataview)",
                url: "https://obsidian.md", websiteSlug: "obsidian"),
            AppAlternative(id: "apple-notes", name: "Apple Notes", typicalMB: 70, savingsMB: 430,
                difficulty: .easy, tradeoff: "Basic formatting, no backlinks, no plugins",
                url: nil, websiteSlug: "apple-notes"),
            AppAlternative(id: "notion-web", name: "Notion (Safari)", typicalMB: 250, savingsMB: 250,
                difficulty: .easy, tradeoff: "No offline support",
                url: "https://notion.so", websiteSlug: "notion-web"),
        ],
        websiteSlug: "notion"
    ),

    // MARK: - API Clients

    AppOffender(
        processNames: ["Postman", "Postman Helper"],
        displayName: "Postman",
        category: "API Client",
        typicalMB: 500,
        icon: "arrow.right.arrow.left",
        alternatives: [
            AppAlternative(id: "bruno", name: "Bruno", typicalMB: 120, savingsMB: 380,
                difficulty: .easy, tradeoff: "Fewer integrations, no cloud sync (git-based)",
                url: "https://www.usebruno.com", websiteSlug: "bruno"),
            AppAlternative(id: "httpie", name: "HTTPie", typicalMB: 170, savingsMB: 330,
                difficulty: .easy, tradeoff: "Smaller ecosystem than Postman",
                url: "https://httpie.io", websiteSlug: "httpie"),
            AppAlternative(id: "insomnia", name: "Insomnia", typicalMB: 350, savingsMB: 150,
                difficulty: .easy, tradeoff: "Fewer collab features, changed pricing recently",
                url: "https://insomnia.rest", websiteSlug: "insomnia"),
            AppAlternative(id: "curl", name: "curl (CLI)", typicalMB: 5, savingsMB: 495,
                difficulty: .hard, tradeoff: "No GUI, steep curve for complex workflows",
                url: nil, websiteSlug: nil),
        ],
        websiteSlug: "postman"
    ),

    // MARK: - Database Clients

    AppOffender(
        processNames: ["DBeaver"],
        displayName: "DBeaver",
        category: "Database",
        typicalMB: 1500,
        icon: "cylinder",
        alternatives: [
            AppAlternative(id: "tableplus", name: "TablePlus", typicalMB: 100, savingsMB: 1400,
                difficulty: .easy, tradeoff: "Fewer DB types in free tier, no ER diagrams",
                url: "https://tableplus.com", websiteSlug: "tableplus"),
            AppAlternative(id: "datagrip", name: "DataGrip", typicalMB: 1000, savingsMB: 500,
                difficulty: .easy, tradeoff: "Still Java-based but better optimized, paid",
                url: "https://jetbrains.com/datagrip/", websiteSlug: "datagrip"),
        ],
        websiteSlug: "dbeaver"
    ),

    AppOffender(
        processNames: ["MongoDB Compass"],
        displayName: "MongoDB Compass",
        category: "Database",
        typicalMB: 500,
        icon: "cylinder",
        alternatives: [
            AppAlternative(id: "mongosh", name: "mongosh (CLI)", typicalMB: 40, savingsMB: 460,
                difficulty: .medium, tradeoff: "No visual query builder, no schema viz",
                url: nil, websiteSlug: "mongosh"),
            AppAlternative(id: "tableplus-mongo", name: "TablePlus", typicalMB: 100, savingsMB: 400,
                difficulty: .easy, tradeoff: "Less MongoDB-specific features",
                url: "https://tableplus.com", websiteSlug: "tableplus"),
        ],
        websiteSlug: "mongodb-compass"
    ),

    AppOffender(
        processNames: ["pgAdmin4", "pgadmin"],
        displayName: "pgAdmin",
        category: "Database",
        typicalMB: 300,
        icon: "cylinder",
        alternatives: [
            AppAlternative(id: "tableplus-pg", name: "TablePlus", typicalMB: 100, savingsMB: 200,
                difficulty: .easy, tradeoff: "Fewer admin features, simpler UI",
                url: "https://tableplus.com", websiteSlug: "tableplus"),
            AppAlternative(id: "psql", name: "psql (CLI)", typicalMB: 10, savingsMB: 290,
                difficulty: .medium, tradeoff: "No GUI, need to learn psql commands",
                url: nil, websiteSlug: nil),
        ],
        websiteSlug: "pgadmin"
    ),

    // MARK: - Design

    AppOffender(
        processNames: ["Figma", "Figma Helper"],
        displayName: "Figma",
        category: "Design",
        typicalMB: 800,
        icon: "paintbrush",
        alternatives: [
            AppAlternative(id: "figma-safari", name: "Figma (Safari)", typicalMB: 500, savingsMB: 300,
                difficulty: .easy, tradeoff: "No offline support, occasional rendering differences",
                url: "https://figma.com", websiteSlug: "figma-safari"),
        ],
        websiteSlug: "figma"
    ),

    // MARK: - Music

    AppOffender(
        processNames: ["Spotify", "Spotify Helper"],
        displayName: "Spotify",
        category: "Music",
        typicalMB: 400,
        icon: "music.note",
        alternatives: [
            AppAlternative(id: "apple-music", name: "Apple Music", typicalMB: 150, savingsMB: 250,
                difficulty: .easy, tradeoff: "Different library/playlists, no Spotify Connect",
                url: nil, websiteSlug: "apple-music"),
            AppAlternative(id: "spotify-web", name: "Spotify (Safari)", typicalMB: 200, savingsMB: 200,
                difficulty: .easy, tradeoff: "No offline, no global media key customization",
                url: "https://open.spotify.com", websiteSlug: "spotify-web"),
        ],
        websiteSlug: "spotify"
    ),

    // MARK: - Terminals

    AppOffender(
        processNames: ["iTerm2"],
        displayName: "iTerm2",
        category: "Terminal",
        typicalMB: 120,
        icon: "terminal",
        alternatives: [
            AppAlternative(id: "ghostty", name: "Ghostty", typicalMB: 40, savingsMB: 80,
                difficulty: .easy, tradeoff: "Newer, fewer integrations than iTerm2",
                url: "https://ghostty.org", websiteSlug: "ghostty"),
            AppAlternative(id: "alacritty", name: "Alacritty", typicalMB: 25, savingsMB: 95,
                difficulty: .medium, tradeoff: "No tabs/splits (use tmux), minimal config",
                url: "https://alacritty.org", websiteSlug: "alacritty"),
            AppAlternative(id: "kitty", name: "Kitty", typicalMB: 40, savingsMB: 80,
                difficulty: .medium, tradeoff: "Different keybinding system",
                url: "https://sw.kovidgoyal.net/kitty/", websiteSlug: "kitty"),
            AppAlternative(id: "terminal-app", name: "Terminal.app", typicalMB: 40, savingsMB: 80,
                difficulty: .easy, tradeoff: "No split panes, limited customization",
                url: nil, websiteSlug: nil),
        ],
        websiteSlug: "iterm2"
    ),

    AppOffender(
        processNames: ["Warp"],
        displayName: "Warp",
        category: "Terminal",
        typicalMB: 250,
        icon: "terminal",
        alternatives: [
            AppAlternative(id: "ghostty-warp", name: "Ghostty", typicalMB: 40, savingsMB: 210,
                difficulty: .easy, tradeoff: "No AI features, no block-based input",
                url: "https://ghostty.org", websiteSlug: "ghostty"),
            AppAlternative(id: "kitty-warp", name: "Kitty", typicalMB: 40, savingsMB: 210,
                difficulty: .medium, tradeoff: "No AI, different UX paradigm",
                url: "https://sw.kovidgoyal.net/kitty/", websiteSlug: "kitty"),
        ],
        websiteSlug: "warp"
    ),

    // MARK: - Email

    AppOffender(
        processNames: ["Superhuman", "Superhuman Helper"],
        displayName: "Superhuman",
        category: "Email",
        typicalMB: 500,
        icon: "envelope",
        alternatives: [
            AppAlternative(id: "apple-mail", name: "Apple Mail", typicalMB: 100, savingsMB: 400,
                difficulty: .easy, tradeoff: "No keyboard-first workflow, less snappy search",
                url: nil, websiteSlug: "apple-mail"),
            AppAlternative(id: "mimestream", name: "Mimestream", typicalMB: 80, savingsMB: 420,
                difficulty: .easy, tradeoff: "Gmail-only, fewer power features",
                url: "https://mimestream.com", websiteSlug: "mimestream"),
        ],
        websiteSlug: "superhuman"
    ),

    AppOffender(
        processNames: ["Outlook", "Microsoft Outlook"],
        displayName: "Outlook",
        category: "Email",
        typicalMB: 600,
        icon: "envelope",
        alternatives: [
            AppAlternative(id: "apple-mail-outlook", name: "Apple Mail", typicalMB: 100, savingsMB: 500,
                difficulty: .easy, tradeoff: "Less Exchange integration, simpler calendar",
                url: nil, websiteSlug: "apple-mail"),
        ],
        websiteSlug: "outlook"
    ),

    // MARK: - Misc Dev Tools

    AppOffender(
        processNames: ["Linear", "Linear Helper"],
        displayName: "Linear",
        category: "Project Management",
        typicalMB: 400,
        icon: "list.bullet.rectangle",
        alternatives: [
            AppAlternative(id: "linear-web", name: "Linear (Safari)", typicalMB: 200, savingsMB: 200,
                difficulty: .easy, tradeoff: "No offline, slightly slower load",
                url: "https://linear.app", websiteSlug: "linear-web"),
        ],
        websiteSlug: "linear"
    ),

    AppOffender(
        processNames: ["1Password", "1Password 7"],
        displayName: "1Password",
        category: "Security",
        typicalMB: 200,
        icon: "lock",
        alternatives: [
            AppAlternative(id: "keychain", name: "iCloud Keychain", typicalMB: 30, savingsMB: 170,
                difficulty: .easy, tradeoff: "No cross-platform, fewer sharing features",
                url: nil, websiteSlug: nil),
        ],
        websiteSlug: "1password"
    ),

    AppOffender(
        processNames: ["Insomnia"],
        displayName: "Insomnia",
        category: "API Client",
        typicalMB: 350,
        icon: "arrow.right.arrow.left",
        alternatives: [
            AppAlternative(id: "bruno-ins", name: "Bruno", typicalMB: 120, savingsMB: 230,
                difficulty: .easy, tradeoff: "Git-based, no cloud sync",
                url: "https://www.usebruno.com", websiteSlug: "bruno"),
            AppAlternative(id: "httpie-ins", name: "HTTPie", typicalMB: 170, savingsMB: 180,
                difficulty: .easy, tradeoff: "Smaller ecosystem",
                url: "https://httpie.io", websiteSlug: "httpie"),
        ],
        websiteSlug: "insomnia"
    ),
]

// MARK: - Matching Engine

struct AppRecommendation {
    let offender: AppOffender
    let currentMB: Int       // actual measured RAM
    let alternatives: [AppAlternative]
    let potentialSavingsMB: Int  // best alternative savings

    var potentialSavingsFormatted: String {
        potentialSavingsMB >= 1024
            ? String(format: "%.1f GB", Double(potentialSavingsMB) / 1024)
            : "\(potentialSavingsMB) MB"
    }
}

/// Match running processes against the offender database and return recommendations.
func getAppRecommendations(processes: [ProcessInfo_Memory]) -> [AppRecommendation] {
    var recommendations: [AppRecommendation] = []

    for offender in appAlternativesDatabase {
        // Find matching process
        let matched = processes.first { proc in
            offender.processNames.contains(where: { procName in
                proc.name.contains(procName) || procName.contains(proc.name)
            })
        }

        guard let proc = matched else { continue }

        // Only recommend if actual usage exceeds a meaningful threshold
        guard proc.memoryMB >= 200 else { continue }

        // Scale savings based on actual usage vs typical
        let scaleFactor = Double(proc.memoryMB) / Double(offender.typicalMB)
        let scaledAlts = offender.alternatives.map { alt -> AppAlternative in
            let scaledSavings = Int(Double(alt.savingsMB) * scaleFactor)
            return AppAlternative(
                id: alt.id, name: alt.name, typicalMB: alt.typicalMB,
                savingsMB: max(scaledSavings, 0), difficulty: alt.difficulty,
                tradeoff: alt.tradeoff, url: alt.url, websiteSlug: alt.websiteSlug
            )
        }

        let bestSavings = scaledAlts.map(\.savingsMB).max() ?? 0

        recommendations.append(AppRecommendation(
            offender: offender,
            currentMB: proc.memoryMB,
            alternatives: scaledAlts,
            potentialSavingsMB: bestSavings
        ))
    }

    // Sort by potential savings descending
    recommendations.sort { $0.potentialSavingsMB > $1.potentialSavingsMB }
    return recommendations
}
