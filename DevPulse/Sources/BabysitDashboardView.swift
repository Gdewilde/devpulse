import SwiftUI

/// The Babysit Dashboard: replayable timeline of `devpulse babysit` sessions.
/// Headline Pro feature for v1.4.0 — visual proof of the babysit workflow,
/// the demo-able artefact of the local-AI co-pilot story.
struct BabysitDashboardView: View {
    @State private var sessions: [BabysitSessionStore.Session] = []
    @State private var selected: BabysitSessionStore.Session?

    var body: some View {
        HSplitView {
            sessionList
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
            sessionDetail
                .frame(minWidth: 480)
        }
        .frame(minWidth: 820, minHeight: 520)
        .onAppear { reload() }
    }

    // MARK: - Session list (left pane)

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Babysit Sessions")
                    .font(.headline)
                Spacer()
                Button(action: reload) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
            .padding(12)

            Divider()

            if sessions.isEmpty {
                emptyState
            } else {
                List(selection: Binding(
                    get: { selected?.id },
                    set: { newID in selected = sessions.first { $0.id == newID } }
                )) {
                    ForEach(sessions) { session in
                        SessionRow(session: session)
                            .tag(session.id)
                            .contextMenu {
                                Button("Delete") {
                                    BabysitSessionStore.deleteSession(session)
                                    reload()
                                }
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([session.url])
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No babysit sessions yet")
                .font(.headline)
            Text("Run `devpulse babysit` from your terminal to start your first session.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Session detail (right pane)

    @ViewBuilder
    private var sessionDetail: some View {
        if let session = selected {
            SessionDetailView(session: session)
        } else if let first = sessions.first {
            SessionDetailView(session: first)
                .onAppear { selected = first }
        } else {
            VStack(spacing: 8) {
                Text("Select a session to replay")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func reload() {
        sessions = BabysitSessionStore.listSessions()
    }
}

// MARK: - Session list row

private struct SessionRow: View {
    let session: BabysitSessionStore.Session

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(formattedStart)
                .font(.system(size: 13, weight: .medium))
            Text(session.summaryLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if session.cleanupRuns > 0 {
                    badge("\(session.cleanupRuns) cleanups", color: .orange)
                }
                if let elapsed = session.elapsed {
                    badge(formatDuration(elapsed), color: .secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var formattedStart: String {
        guard let date = session.startedAt else { return session.id }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Session detail (timeline + summary)

private struct SessionDetailView: View {
    let session: BabysitSessionStore.Session

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            timeline
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formattedStart)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Text(session.id)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 24) {
                stat("Ticks", "\(session.ticks)")
                stat("Cleanups", "\(session.cleanupRuns)")
                stat("Reclaimed", reclaimedString)
                stat("Target free", "\(session.targetFreeMB) MB")
                if let elapsed = session.elapsed {
                    stat("Elapsed", formatDuration(elapsed))
                }
            }
        }
        .padding(20)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
        }
    }

    private var formattedStart: String {
        guard let date = session.startedAt else { return session.id }
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        return f.string(from: date)
    }

    private var reclaimedString: String {
        let mb = session.totalReclaimedMB
        return mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
    }

    // MARK: - Timeline

    private var timeline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(session.events) { event in
                    EventRow(event: event)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Event row (one line per babysit event)

private struct EventRow: View {
    let event: BabysitSessionStore.Event

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(timestampText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 64, alignment: .leading)

            Circle()
                .fill(eventColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(event.kind)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(eventColor)
                    if let pressure = event.pressure, !pressure.isEmpty {
                        Text(pressure)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                }
                Text(detailLine)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                if event.kind == "cleanup" && !event.actions.isEmpty {
                    ForEach(event.actions, id: \.self) { action in
                        Text("• \(action)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private var timestampText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: event.timestamp)
    }

    private var eventColor: Color {
        switch event.kind {
        case "started": return .blue
        case "tick":    return .secondary
        case "cleanup": return .orange
        case "done":    return .green
        default:        return .secondary
        }
    }

    private var detailLine: String {
        switch event.kind {
        case "tick":
            var parts: [String] = []
            if let mb = event.availableForAIMB {
                parts.append("free \(mb) MB")
            }
            if let pct = event.memUsedPercent { parts.append("mem \(pct)%") }
            if let swap = event.swapGB { parts.append(String(format: "swap %.1f GB", swap)) }
            if let bat = event.batteryPercent { parts.append("battery \(bat)%") }
            return parts.joined(separator: "  ")
        case "cleanup":
            if let r = event.reclaimedMB {
                return "reclaimed \(r) MB"
            }
            return ""
        case "started":
            return "session opened"
        case "done":
            return "session closed cleanly"
        default:
            return ""
        }
    }
}

// MARK: - Helpers

private func formatDuration(_ interval: TimeInterval) -> String {
    let total = Int(interval)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m \(s)s" }
    return "\(s)s"
}
