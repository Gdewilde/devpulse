import SwiftUI
import AppKit

// MARK: - Settings Window (Tabbed)

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var prefs: Preferences
    var onAction: (AppAction) -> Void

    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                SettingsTab(icon: "gearshape", label: "General", selected: selectedTab == 0) { selectedTab = 0 }
                SettingsTab(icon: "bell", label: "Notifications", selected: selectedTab == 1) { selectedTab = 1 }
                SettingsTab(icon: "bolt", label: "Optimizer", selected: selectedTab == 2) { selectedTab = 2 }
                SettingsTab(icon: "person.2", label: "Profiles", selected: selectedTab == 3) { selectedTab = 3 }
                SettingsTab(icon: "brain", label: "Learning", selected: selectedTab == 4) { selectedTab = 4 }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider().padding(.top, 8)

            // Tab content
            ScrollView {
                switch selectedTab {
                case 0: GeneralSettingsTab(prefs: prefs)
                case 1: NotificationSettingsTab(prefs: prefs)
                case 2: OptimizerSettingsTab(prefs: prefs)
                case 3: ProfilesSettingsTab(state: state, onAction: onAction)
                case 4: LearningSettingsTab(state: state, prefs: prefs, onAction: onAction)
                default: EmptyView()
                }
            }
        }
        .frame(width: 480, height: 460)
    }
}

struct SettingsTab: View {
    let icon: String
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? .blue : .secondary)
            .background(selected ? Color.blue.opacity(0.08) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: "Startup") {
                Toggle("Launch DevPulse at login", isOn: $prefs.launchAtLogin)
            }

            SettingsGroup(title: "Menu Bar") {
                Toggle("Show memory percentage", isOn: $prefs.showPercentInMenuBar)
                Toggle("Show swap indicator", isOn: $prefs.showSwapInMenuBar)
            }

            SettingsGroup(title: "Refresh") {
                HStack {
                    Text("Refresh interval")
                    Spacer()
                    Picker("", selection: $prefs.refreshIntervalSec) {
                        Text("3 sec").tag(3)
                        Text("5 sec").tag(5)
                        Text("10 sec").tag(10)
                        Text("30 sec").tag(30)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
            }
        }
        .padding(20)
    }
}

// MARK: - Notifications

struct NotificationSettingsTab: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: "Alerts") {
                Toggle("Zombie processes detected", isOn: $prefs.notifyZombies)
                Toggle("Swap growth warnings", isOn: $prefs.notifySwapGrowth)

                Toggle("Memory pressure alert", isOn: $prefs.notifyMemoryPressure)
                if prefs.notifyMemoryPressure {
                    HStack {
                        Text("Alert when usage exceeds")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $prefs.memoryPressureThresholdPct) {
                            Text("75%").tag(75)
                            Text("80%").tag(80)
                            Text("85%").tag(85)
                            Text("90%").tag(90)
                            Text("95%").tag(95)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 80)
                    }
                    .padding(.leading, 20)
                }
            }
        }
        .padding(20)
    }
}

// MARK: - Optimizer

struct OptimizerSettingsTab: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: "Zombies") {
                Toggle("Auto-kill zombie processes", isOn: $prefs.autoKillZombies)
                if prefs.autoKillZombies {
                    HStack {
                        Text("Kill after idle for")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $prefs.zombieMinAgeMin) {
                            Text("15 min").tag(15)
                            Text("30 min").tag(30)
                            Text("60 min").tag(60)
                            Text("2 hours").tag(120)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)
                    }
                    .padding(.leading, 20)
                }
            }

            SettingsGroup(title: "Chrome") {
                HStack {
                    Text("Warn when Chrome exceeds")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { Int(prefs.chromeWarnGB) },
                        set: { prefs.chromeWarnGB = Double($0) }
                    )) {
                        Text("6 GB").tag(6)
                        Text("8 GB").tag(8)
                        Text("10 GB").tag(10)
                        Text("15 GB").tag(15)
                        Text("20 GB").tag(20)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 80)
                }
            }

            SettingsGroup(title: "Schedule") {
                HStack {
                    Text("Run optimizer every")
                    Spacer()
                    Picker("", selection: $prefs.optimizerIntervalMin) {
                        Text("2 min").tag(2)
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 80)
                }
            }
        }
        .padding(20)
    }
}

// MARK: - Profiles

struct ProfilesSettingsTab: View {
    @ObservedObject var state: AppState
    var onAction: (AppAction) -> Void
    @State private var editingProfile: SessionProfile? = nil
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Manage your workspace profiles")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    isCreating = true
                } label: {
                    Label("New Profile", systemImage: "plus")
                        .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            ForEach(state.sessionProfileManager.profiles) { profile in
                ProfileSettingsRow(
                    profile: profile,
                    onEdit: { editingProfile = profile },
                    onDelete: { onAction(.deleteProfile(profile.id)) }
                )
            }

            HStack {
                Button("Reset to Defaults") {
                    state.sessionProfileManager.resetToDefaults()
                    state.objectWillChange.send()
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)

                Spacer()

                Text("\(state.sessionProfileManager.profiles.count) profiles")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .sheet(item: $editingProfile) { profile in
            ProfileEditorView(
                profile: profile,
                runningApps: state.sessionProfileManager.runningAppNames(),
                onSave: { updated in
                    onAction(.updateProfile(updated))
                    editingProfile = nil
                },
                onCancel: { editingProfile = nil }
            )
        }
        .sheet(isPresented: $isCreating) {
            ProfileEditorView(
                profile: nil,
                runningApps: state.sessionProfileManager.runningAppNames(),
                onSave: { newProfile in
                    onAction(.addProfile(newProfile))
                    isCreating = false
                },
                onCancel: { isCreating = false }
            )
        }
    }
}

// MARK: - Learning

struct LearningSettingsTab: View {
    @ObservedObject var state: AppState
    @ObservedObject var prefs: Preferences
    var onAction: (AppAction) -> Void

    @State private var excludeInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: "Behavior Learning") {
                Toggle("Enable Learn Mode", isOn: Binding(
                    get: { state.sessionProfileManager.learnModeEnabled },
                    set: { _ in onAction(.toggleLearnMode) }
                ))
                Text("DevPulse observes which apps you use together over time and suggests new profiles based on your habits.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if state.sessionProfileManager.learnModeEnabled {
                    HStack {
                        Text("Snapshot interval")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $prefs.learnSnapshotIntervalMin) {
                            Text("1 min").tag(1)
                            Text("5 min").tag(5)
                            Text("10 min").tag(10)
                            Text("15 min").tag(15)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 80)
                    }
                    .padding(.leading, 20)
                }
            }

            if state.sessionProfileManager.learnModeEnabled {
                SettingsGroup(title: "Excluded Apps") {
                    Text("Apps that won't be included in learned patterns.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    FlowLayout(spacing: 4) {
                        ForEach(prefs.learnExcludedApps, id: \.self) { app in
                            HStack(spacing: 3) {
                                Text(app)
                                    .font(.system(size: 11))
                                Button {
                                    prefs.learnExcludedApps.removeAll { $0 == app }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                        }
                    }

                    HStack {
                        TextField("App name to exclude", text: $excludeInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .onSubmit { addExcluded() }
                        Button("Add") { addExcluded() }
                            .disabled(excludeInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !state.sessionProfileManager.runningAppNames().isEmpty {
                        Text("Or tap a running app:")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        FlowLayout(spacing: 4) {
                            ForEach(state.sessionProfileManager.runningAppNames().filter { !prefs.learnExcludedApps.contains($0) }, id: \.self) { app in
                                Button {
                                    prefs.learnExcludedApps.append(app)
                                } label: {
                                    Text(app)
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.primary.opacity(0.05))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    private func addExcluded() {
        let name = excludeInput.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !prefs.learnExcludedApps.contains(name) else { return }
        prefs.learnExcludedApps.append(name)
        excludeInput = ""
    }
}

// MARK: - Shared Components

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .font(.system(size: 13))
        }
    }
}

struct ProfileSettingsRow: View {
    let profile: SessionProfile
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: profile.icon)
                .font(.system(size: 14))
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.system(size: 13, weight: .medium))
                    if profile.isBuiltIn {
                        Text("Built-in")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary.opacity(0.3), in: Capsule())
                    }
                }
                Text(profile.apps.joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isHovered {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.04) : .clear)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Profile Editor (Add / Edit)

struct ProfileEditorView: View {
    let isNew: Bool
    @State private var name: String
    @State private var selectedApps: Set<String>
    @State private var selectedIcon: String
    private let profileId: String
    private let wasBuiltIn: Bool
    let runningApps: [String]
    let onSave: (SessionProfile) -> Void
    let onCancel: () -> Void

    init(profile: SessionProfile?, runningApps: [String], onSave: @escaping (SessionProfile) -> Void, onCancel: @escaping () -> Void) {
        self.isNew = profile == nil
        self.runningApps = runningApps
        self.onSave = onSave
        self.onCancel = onCancel

        let p = profile ?? SessionProfile(id: UUID().uuidString, name: "", apps: [], estimatedRAMGB: 0, icon: "star", isBuiltIn: false)
        self.profileId = p.id
        self.wasBuiltIn = p.isBuiltIn
        _name = State(initialValue: p.name)
        _selectedApps = State(initialValue: Set(p.apps))
        _selectedIcon = State(initialValue: p.icon)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New Profile" : "Edit Profile")
                .font(.system(size: 15, weight: .bold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Profile name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Icon")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 8), spacing: 4) {
                    ForEach(SessionProfile.availableIcons, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 13))
                                .frame(width: 28, height: 28)
                                .background(selectedIcon == icon ? Color.blue.opacity(0.15) : Color.clear)
                                .foregroundStyle(selectedIcon == icon ? .blue : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Apps")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                if !runningApps.isEmpty {
                    Text("Tap running apps to toggle:")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    FlowLayout(spacing: 4) {
                        ForEach(runningApps, id: \.self) { app in
                            let isSelected = selectedApps.contains(app)
                            Button {
                                if isSelected { selectedApps.remove(app) }
                                else { selectedApps.insert(app) }
                            } label: {
                                Text(app)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(isSelected ? Color.blue.opacity(0.15) : Color.primary.opacity(0.05))
                                    .foregroundStyle(isSelected ? .blue : .primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                if !selectedApps.subtracting(Set(runningApps)).isEmpty {
                    Text("Also included (not running):")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                    FlowLayout(spacing: 4) {
                        ForEach(selectedApps.subtracting(Set(runningApps)).sorted(), id: \.self) { app in
                            HStack(spacing: 2) {
                                Text(app)
                                    .font(.system(size: 11))
                                Button {
                                    selectedApps.remove(app)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") {
                    let profile = SessionProfile(
                        id: profileId,
                        name: name,
                        apps: selectedApps.sorted(),
                        estimatedRAMGB: Double(selectedApps.count) * 2,
                        icon: selectedIcon,
                        isBuiltIn: wasBuiltIn
                    )
                    onSave(profile)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || selectedApps.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380, height: 480)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
