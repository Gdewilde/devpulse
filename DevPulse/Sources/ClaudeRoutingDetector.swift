import Foundation

/// Detects which API backend Claude Code is currently routed to by reading
/// `ANTHROPIC_BASE_URL` from the places a GUI app can actually see — the
/// Claude Code settings file and common shell rc files. Useful for
/// surfacing routing posture next to DevPulse's local hybrid-routing row.
///
/// Why not just `getenv`: a SwiftUI menubar app launched from Finder does
/// not inherit shell exports from `.zshrc` / `.bashrc`. We have to look.
enum ClaudeBackend: String {
    case anthropic = "Anthropic"
    case deepseek  = "DeepSeek"
    case openRouter = "OpenRouter"
    case fireworks = "Fireworks"
    case custom    = "Custom"
    case unknown   = "Unknown"

    static func classify(_ url: String?) -> ClaudeBackend {
        guard let raw = url?.lowercased(), !raw.isEmpty else { return .anthropic }
        if raw.contains("api.anthropic.com")    { return .anthropic }
        if raw.contains("deepseek")             { return .deepseek }
        if raw.contains("openrouter")           { return .openRouter }
        if raw.contains("fireworks")            { return .fireworks }
        return .custom
    }
}

struct ClaudeRouting {
    let backend: ClaudeBackend
    let baseURL: String?
    /// Where we found the override, e.g. "~/.claude/settings.json" or "~/.zshrc".
    let source: String?
}

enum ClaudeRoutingDetector {
    static func detect() -> ClaudeRouting {
        if let hit = readClaudeSettings() { return hit }
        if let hit = readShellFiles()    { return hit }
        return ClaudeRouting(backend: .anthropic, baseURL: nil, source: nil)
    }

    // ~/.claude/settings.json — { "env": { "ANTHROPIC_BASE_URL": "..." } }
    private static func readClaudeSettings() -> ClaudeRouting? {
        let path = ("~/.claude/settings.json" as NSString).expandingTildeInPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env  = json["env"] as? [String: Any],
              let url  = env["ANTHROPIC_BASE_URL"] as? String, !url.isEmpty
        else { return nil }
        return ClaudeRouting(backend: .classify(url), baseURL: url, source: "~/.claude/settings.json")
    }

    // Grep common rc files for `export ANTHROPIC_BASE_URL=...`. Last hit wins.
    private static func readShellFiles() -> ClaudeRouting? {
        let candidates = ["~/.zshenv", "~/.zshrc", "~/.bash_profile", "~/.bashrc", "~/.profile"]
        let pattern = #"ANTHROPIC_BASE_URL\s*=\s*["']?([^"'\s]+)["']?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        var found: ClaudeRouting? = nil
        for rel in candidates {
            let path = (rel as NSString).expandingTildeInPath
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            // Walk lines so a commented-out export is ignored.
            for line in text.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") { continue }
                let ns = trimmed as NSString
                let range = NSRange(location: 0, length: ns.length)
                guard let m = regex.firstMatch(in: trimmed, range: range), m.numberOfRanges >= 2 else { continue }
                let url = ns.substring(with: m.range(at: 1))
                found = ClaudeRouting(backend: .classify(url), baseURL: url, source: rel)
            }
        }
        return found
    }
}
