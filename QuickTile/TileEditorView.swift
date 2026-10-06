import SwiftUI
import UIKit
import QuickTileCore

struct TileEditorView: View {
    let pageID: UUID
    let tile: Tile?
    let insertionSlot: Int?
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .app
    @State private var name = ""
    @State private var iconSymbol = "globe"
    @State private var appID = ""
    @State private var shortcutID = ""
    @State private var url = "https://"
    @State private var key = "space"
    @State private var modifiers: [KeyModifier] = []
    @State private var targetID = ""
    @State private var timerMinutes = 5
    @State private var timerSeconds = 0
    @State private var timerHaptic = TimerHapticPattern.click
    @State private var media: MediaCommand = .playPause
    @State private var destination: UUID?
    @State private var detail: String?
    @State private var search = ""
    @State private var deleting = false
    @State private var choosingAction = false
    @State private var fixedAction: DeckAction = .media(.playPause)
    @State private var presetID: String?
    @State private var populated = false
    @State private var showConfiguration = false
    @State private var sequence = ActionSequence()
    @State private var customIconReference: String?
    @State private var targetOverride: String?
    @State private var configuredShortcut: QuickTileCore.KeyboardShortcut?
    @State private var agentSource = AgentSource.unknown
    @State private var agentLauncher = ""
    @State private var testing = false
    @State private var testedTileID: UUID?
    @State private var testResult: TestFeedback?
    private struct TestFeedback {
        let message: String
        let succeeded: Bool
    }
    init(pageID: UUID, tile: Tile?, insertionSlot: Int? = nil) {
        self.pageID = pageID; self.tile = tile; self.insertionSlot = insertionSlot
    }
    enum Kind: String, CaseIterable, Identifiable {
        case sequence = "Sequence", timer = "Timer", app = "Mac app", keyboard = "Keyboard", music = "Media", volumeDial = "Volume dial", brightnessDial = "Brightness dial", shortcut = "Apple Shortcut", website = "Website", builtIn = "Control"
        var id: Self { self }
        var symbol: String { switch self { case .sequence: "list.bullet.rectangle"; case .timer: "timer"; case .app: "app"; case .keyboard: "keyboard"; case .music: "playpause.fill"; case .volumeDial: "speaker.wave.2"; case .brightnessDial: "sun.max"; case .shortcut: "square.stack.3d.up"; case .website: "globe"; case .builtIn: "slider.horizontal.3" } }
    }
    var body: some View {
        NavigationStack {
            if tile == nil {
                ActionLibraryView { item in select(item); showConfiguration = true }
                    .navigationDestination(isPresented: $showConfiguration) { configuration }
            } else {
                configuration.navigationDestination(isPresented: $choosingAction) {
                    ActionLibraryView { item in select(item); choosingAction = false }
                }
            }
        }
    }
    private var configuration: some View {
            Form {
                Section {
                    if tile != nil {
                        Button { choosingAction = true } label: { Label(name.isEmpty ? "Choose action" : name, systemImage: fixedAction.fixedSymbol ?? iconSymbol) }.accessibilityIdentifier("actionPicker")
                    } else { Label(name, systemImage: fixedAction.fixedSymbol ?? iconSymbol) }
                    if kind == .app || kind == .website || kind == .keyboard || kind == .shortcut || kind == .sequence {
                        TextField("Name", text: $name).accessibilityIdentifier("tileName")
                    }
                    if (model.layout?.pages.count ?? 0) > 1 {
                        Picker("Board", selection: $destination) { ForEach(model.layout?.pages ?? []) { board in Label { Text(board.name) } icon: { BoardIcon(board: board).frame(width: 20, height: 20) }.tag(Optional(board.id)) } }
                    }
                    if (kind == .keyboard && presetID == nil) || kind == .website || kind == .shortcut {
                        NavigationLink { IconSettingsView(symbol: $iconSymbol, reference: $customIconReference, website: kind == .website) } label: { Label("Icon", systemImage: iconSymbol) }
                    }
                }
                actionFields
                if tile != nil || kind == .sequence || presetID != nil {
                    Section {
                        Button(action: testAction) {
                            HStack {
                                Text("Test action")
                                Spacer()
                                if testing { ProgressView().accessibilityLabel("Testing action") }
                            }
                        }.disabled(testing)
                        if let testedTileID, let progress = model.sequenceProgress[testedTileID] {
                            Text("Step \(progress.stepIndex + 1) of \(progress.stepCount): \(progress.title)").font(.callout).foregroundStyle(.secondary)
                            Button("Stop test") { model.cancel(tileID: testedTileID) }
                        }
                        if let testResult {
                            Label(testResult.message, systemImage: testResult.succeeded ? "checkmark.circle" : "exclamationmark.circle")
                                .font(.callout).foregroundStyle(testResult.succeeded ? Color.secondary : .red)
                                .accessibilityIdentifier("testResult")
                        }
                    } footer: { if presetID != nil { Text("Open a disposable document and focus the relevant timeline or panel before testing.") } }
                }
                if let detail { Section { Label(detail, systemImage: "exclamationmark.circle").font(.callout) } }
                if tile != nil { Section { Button("Delete tile", role: .destructive) { deleting = true } } }
            }
            .navigationTitle(tile == nil ? "Add tile" : "Edit tile").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { if tile != nil { Button("Cancel") { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold).disabled(testing).accessibilityIdentifier("saveTile") }
            }
            .onAppear { if !populated { populate(); populated = true } }
            .onChange(of: kind) { old, new in
                detail = nil; search = ""
                if name.isEmpty || name == old.rawValue { name = new.rawValue }
                if tile == nil || iconSymbol == old.symbol || iconSymbol == "globe" { iconSymbol = new.symbol }
            }
            .confirmationDialog("Delete this tile?", isPresented: $deleting) { Button("Delete tile", role: .destructive) { if let tile { model.removeTile(tile, boardID: pageID) }; dismiss() } }
    }
    private func testAction() {
        guard !testing else { return }
        do {
            let candidate = try draft()
            detail = nil; testResult = nil; testing = true; testedTileID = candidate.id
            model.test(tile: candidate) { message, succeeded in
                testing = false
                testResult = TestFeedback(message: message, succeeded: succeeded)
            }
        } catch {
            testResult = TestFeedback(message: error.localizedDescription, succeeded: false)
            model.feedback(.error)
        }
    }
    @ViewBuilder private var actionFields: some View {
        switch kind {
        case .sequence: SequenceEditorView(sequence: $sequence)
        case .timer:
            Section("Duration") {
                Picker("Minutes", selection: $timerMinutes) { ForEach(0...60, id: \.self) { Text("\($0) min").tag($0) } }
                Picker("Seconds", selection: $timerSeconds) { ForEach(0...59, id: \.self) { Text("\($0) sec").tag($0) } }.disabled(timerMinutes == 60)
            }
            .onChange(of: timerMinutes) { _, value in if value == 60 { timerSeconds = 0 } }
            Section("When finished") {
                Picker("Haptic", selection: $timerHaptic) {
                    ForEach(TimerHapticPattern.allCases) { Text($0.label).tag($0) }
                }.accessibilityIdentifier("timerHapticPicker")
                Button("Preview haptic") { model.playTimerHaptic(timerHaptic) }.disabled(timerHaptic == .off || model.layout?.settings.haptics == false)
            }
            Section { Text("Tap to start or pause. Use the reset arrow to start over. When finished, tap the tile to stop the haptic reminder. Haptics repeat while QuickTile is open.").font(.caption).foregroundStyle(.secondary) }
        case .builtIn:
            if case .assistant = fixedAction {
                Section {
                    Text("Tap to speak. Tap again to send your command.")
                    Text("Add your Groq API key in Mac Settings. Audio stays on your iPhone; the transcript and available app and Shortcut names go to Groq.").foregroundStyle(.secondary)
                    Text("Controls installed apps, websites, volume, brightness, playback, Apple Shortcuts, and supported editing commands.").foregroundStyle(.secondary)
                }.font(.callout)
            } else if case .agent(let provider) = fixedAction {
                Section {
                    Picker("Sessions", selection: $agentSource) {
                        Text("All sessions").tag(AgentSource.unknown)
                        ForEach([AgentSource.desktop, .terminal], id: \.self) { source in
                            let supported = model.agentSnapshot(provider, source: source)?.updatedAt != nil
                            if supported || agentSource == source { Text(supported ? source.label : "\(source.label) (unavailable)").tag(source) }
                        }
                    }
                    let snapshot = model.agentSnapshot(provider, source: agentSource)
                    Label(snapshot?.phase.label ?? "Status unavailable", systemImage: provider.symbol)
                    if let health = snapshot?.health { Text(health.label).foregroundStyle(.secondary) }
                    if agentSource != .unknown, snapshot?.updatedAt == nil { Text("Use All sessions until this integration supplies source information.").foregroundStyle(.secondary) }
                    NavigationLink(model.appByID[agentLauncher]?.name ?? "Default launcher") { CatalogPickerView(kind: .app, choose: { _, _ in }, selection: $agentLauncher) }
                    Text("Shows local desktop and terminal sessions. Waiting for input takes priority when several sessions are active.")
                    Text("Enable tracking in Mac Settings. Codex hooks also need trust in /hooks. Opening a terminal app does not focus a specific session.").foregroundStyle(.secondary)
                }.font(.callout)
            } else if case .preset(let id) = fixedAction, let preset = ActionLibrary.preset(id: id) {
                Section {
                    Text((configuredShortcut ?? preset.shortcut)?.displayText ?? "").font(.title3.monospaced())
                    let candidates = AppProfiles.profile(bundleID: preset.bundleID).map { AppProfiles.candidates(profileID: $0.id, apps: model.apps) } ?? []
                    if candidates.count > 1 {
                        Picker("App version", selection: Binding(get: { targetOverride ?? "" }, set: { targetOverride = $0.isEmpty ? nil : $0 })) { Text("Mac default").tag(""); ForEach(candidates) { Text($0.name).tag($0.id) } }
                    }
                    Button("Customize shortcut") {
                        if let shortcut = configuredShortcut ?? preset.shortcut { key = shortcut.key; modifiers = shortcut.modifiers; targetID = targetOverride ?? shortcut.targetBundleID ?? ""; kind = .keyboard }
                    }
                } header: { Text(preset.appName) } footer: { Text("Uses the app’s default Mac shortcuts. The relevant editor or timeline must have focus.") }
            } else if case .preset = fixedAction {
                Section { Label("This action is unavailable. Choose a replacement above.", systemImage: "exclamationmark.circle") }
            }
        case .volumeDial, .brightnessDial:
            Section {
                Text(kind == .volumeDial ? "Turn the dial to adjust your Mac’s output volume." : "Turn the dial to adjust your Mac’s built-in or supported Apple display brightness.")
                    .font(.caption).foregroundStyle(.secondary)
                if kind == .brightnessDial { DisplaySelector(store: model.controls, choose: model.selectDisplay) }
            }
        case .app:
            Section("Application") {
                catalogState
                HStack {
                    Text("\(model.apps.count) Mac apps").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { model.refreshCatalog() }.disabled(model.state != .connected)
                }
                NavigationLink {
                    CatalogPickerView(kind: .app, choose: { _, title in if name.isEmpty || tile == nil { name = title } }, selection: $appID)
                } label: {
                    HStack {
                        if let app = model.appByID[appID] { CatalogIcon(app: app) }
                        Text(model.appByID[appID]?.name ?? (appID.isEmpty ? "Choose a Mac app" : appID))
                    }
                }
            }
        case .keyboard:
            Section("Key combination") {
                Picker("Key", selection: $key) { ForEach(KeyboardShortcut.keyCodes.keys.sorted(), id: \.self) { Text($0.uppercased()).tag($0) } }
                ForEach(KeyModifier.allCases, id: \.self) { modifier in
                    Toggle("\(modifier.symbol)  \(modifier.rawValue.capitalized)", isOn: Binding(get: { modifiers.contains(modifier) }, set: { enabled in if enabled { modifiers.append(modifier) } else { modifiers.removeAll { $0 == modifier } } }))
                }
            }
            Section {
                NavigationLink(model.appByID[targetID]?.name ?? (targetID.isEmpty ? "Current foreground app" : targetID)) {
                    CatalogPickerView(kind: .app, allowsForeground: true, choose: { _, _ in }, selection: $targetID)
                }
            } header: { Text("Send keys to") } footer: { Text("Requires Accessibility on your Mac. Uses physical key positions.") }
        case .music:
            Section("Media") {
                Picker("Control", selection: $media) { Text("Play / pause").tag(MediaCommand.playPause); Text("Previous track").tag(MediaCommand.previous); Text("Next track").tag(MediaCommand.next) }
                Picker("Player", selection: Binding(get: { targetOverride ?? "" }, set: { targetOverride = $0.isEmpty ? nil : $0 })) {
                    Text("Mac playback").tag("")
                    ForEach(MediaPlayer.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Text(targetOverride == nil ? "Uses the Mac’s media keys, including browser video. Playback state is unavailable for system media keys." : "Uses this player’s supported controls and observes playback state. Allow Automation on the Mac when first used.").font(.caption).foregroundStyle(.secondary)
            }
        case .shortcut:
            Section("Shortcuts on your Mac") {
                catalogState
                if let note = model.catalogNote { Text(note).font(.caption) }
                if model.shortcuts.isEmpty { Text("No shortcuts received. Open Shortcuts on the Mac, then refresh the catalog in the companion.").font(.caption).foregroundStyle(.secondary) }
                NavigationLink(model.shortcuts.first { $0.id == shortcutID }?.name ?? "Choose a shortcut") {
                    CatalogPickerView(kind: .shortcut, choose: { _, title in if name.isEmpty || tile == nil { name = title } }, selection: $shortcutID)
                }
                Text("A shortcut can ask for input or permission on the Mac. QuickTile waits up to five minutes for the command-line process to finish. It never retries automatically.").font(.caption).foregroundStyle(.secondary)
            }
        case .website:
            Section("Website") {
                TextField("https://example.com", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("websiteURL")
                Text("Opens in your Mac’s default browser. Choose a custom symbol above or use the website icon when available.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private var catalogState: some View {
        if model.state != .connected { Label("Connect to your Mac to browse its private catalog.", systemImage: "wifi.slash").font(.caption).foregroundStyle(.secondary) }
    }
    private func populate() {
        destination = pageID
        guard let tile else { return }
        fixedAction = tile.action
        name = tile.name
        iconSymbol = tile.symbol
        customIconReference = tile.customIconReference; targetOverride = tile.targetBundleID; configuredShortcut = tile.configuredShortcut
        timerHaptic = tile.timerHaptic ?? .click
        agentSource = tile.agentSource ?? .unknown; agentLauncher = tile.agentLauncherBundleID ?? ""
        presetID = tile.presetID
        switch tile.action {
        case .sequence(let value): kind = .sequence; sequence = value
        case .timer(let seconds): kind = .timer; timerMinutes = seconds / 60; timerSeconds = seconds % 60
        case .preset, .system, .agent, .assistant: kind = .builtIn; fixedAction = tile.action
        case .dial(let control): kind = control == .volume ? .volumeDial : .brightnessDial
        case .launchApp(let id): kind = .app; appID = id
        case .keyboard(let shortcut): kind = .keyboard; key = shortcut.key; modifiers = shortcut.modifiers; targetID = shortcut.targetBundleID ?? ""
        case .music(let command), .media(let command): kind = .music; media = command
        case .volume: kind = .volumeDial
        case .shortcut(let id): kind = .shortcut; shortcutID = id
        case .website(let text): kind = .website; url = text
        }
    }
    private func save() {
        do {
            let saved = try draft()
            guard var layout = model.layout, let target = layout.pages.firstIndex(where: { $0.id == destination }) else { throw QuickTileError.invalid("Choose a page for this tile.") }
            if let tile, let source = layout.pages.firstIndex(where: { $0.id == pageID }), let tileIndex = layout.pages[source].tiles.firstIndex(where: { $0.id == tile.id }) {
                if source == target { layout.pages[source].tiles[tileIndex] = saved }
                else { layout.pages[source].removeTile(tile.id); layout.pages[target].tiles.append(saved) }
            } else { layout.pages[target].tiles.append(saved) }
            if tile == nil, layout.pages[target].id == pageID, let insertionSlot {
                layout.pages[target].place(saved.id, at: insertionSlot)
            }
            model.layout = layout; model.feedback(.success); dismiss()
        } catch { detail = error.localizedDescription; model.feedback(.error) }
    }
    private func draft() throws -> Tile {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try Validation.name(title)
        let action: DeckAction
        switch kind {
        case .sequence: var value = sequence; value.name = title; action = .sequence(value)
        case .timer: action = .timer(seconds: timerMinutes * 60 + timerSeconds)
        case .builtIn: action = fixedAction
        case .volumeDial: action = .dial(.volume)
        case .brightnessDial: action = .dial(.brightness)
        case .app: action = .launchApp(bundleID: appID)
        case .keyboard:
            if let presetID, ActionLibrary.preset(id: presetID) != nil { action = .preset(presetID) }
            else { action = .keyboard(.init(key: key, modifiers: modifiers, targetBundleID: targetID.isEmpty ? nil : targetID)) }
        case .music: action = .media(media)
        case .shortcut: action = .shortcut(identifier: shortcutID)
        case .website: action = .website(url: url)
        }
        try action.validate()
        var saved = Tile(id: tile?.id ?? UUID(), name: title, symbol: action.fixedSymbol ?? iconSymbol, action: action)
        if case .timer = action { saved.timerHaptic = timerHaptic }
        saved.presetID = presetID; saved.targetBundleID = targetOverride; saved.mappingVersion = tile?.mappingVersion ?? 1
        if case .agent = action { saved.agentSource = agentSource; saved.agentLauncherBundleID = agentLauncher.isEmpty ? nil : agentLauncher }
        if kind == .keyboard, let presetID, ActionLibrary.preset(id: presetID) != nil {
            let shortcut = KeyboardShortcut(key: key, modifiers: modifiers, targetBundleID: targetID.isEmpty ? nil : targetID)
            try shortcut.validate(); saved.configuredShortcut = shortcut; saved.targetBundleID = targetID.isEmpty ? nil : targetID
        } else { saved.configuredShortcut = configuredShortcut }
        saved.customIconReference = action.fixedSymbol == nil && kind != .app ? customIconReference : nil
        return saved
    }
    private func select(_ item: LibraryAction) {
        customIconReference = nil; configuredShortcut = nil; targetOverride = nil
        name = item.title; iconSymbol = item.symbol; fixedAction = item.action; presetID = item.preset?.id ?? (item.id.hasPrefix("editing.") ? item.id : nil)
        switch item.action {
        case .sequence(let value): kind = .sequence; sequence = value
        case .timer(let seconds): kind = .timer; timerMinutes = seconds / 60; timerSeconds = seconds % 60
        case .launchApp(let id): kind = .app; appID = id
        case .website: kind = .website
        case .shortcut: kind = .shortcut
        case .keyboard(let shortcut): kind = .keyboard; key = shortcut.key; modifiers = shortcut.modifiers; targetID = shortcut.targetBundleID ?? ""
        case .dial(let control): kind = control == .volume ? .volumeDial : .brightnessDial
        case .media(let command), .music(let command): kind = .music; media = command
        case .preset, .system, .agent, .assistant: kind = .builtIn
        case .volume: kind = .volumeDial
        }
        model.feedback(.selection)
    }
}
private struct DisplaySelector: View {
    @ObservedObject var store: MacControlStore
    let choose: (UInt32) -> Void
    var body: some View {
        let displays = store.state?.displays?.filter { $0.brightness != nil } ?? []
        if displays.count > 1 {
            Picker("Display", selection: Binding(get: { store.state?.displayID ?? displays.first!.id }, set: choose)) { ForEach(displays) { Text($0.name).tag($0.id) } }
        }
    }
}
struct IconChooser: View {
    @EnvironmentObject private var model: PhoneModel
    @Binding var selection: String
    var title = "Button icon"
    private let symbols = [
        "square.grid.2x2", "briefcase", "laptopcomputer", "gamecontroller", "paintbrush", "book", "cup.and.saucer", "moon", "sun.max", "leaf", "dumbbell", "hammer",
        "globe", "safari", "link", "link.circle", "network", "bookmark", "bookmark.fill", "star", "star.fill", "heart", "heart.fill", "bolt", "bolt.fill",
        "sparkles", "wand.and.stars", "magicmouse", "keyboard", "command", "option", "control", "shift", "escape", "return", "delete.left",
        "music.note", "music.mic", "headphones", "speaker.wave.2", "speaker.slash", "play.fill", "forward.fill", "backward.fill", "shuffle", "repeat",
        "square.stack.3d.up", "square.stack.3d.forward.dottedline", "rectangle.stack", "gearshape", "gearshape.2", "slider.horizontal.3", "switch.2", "terminal",
        "camera", "camera.fill", "photo", "photo.on.rectangle", "video", "mic", "house", "building.2", "folder", "folder.fill", "doc.text", "doc.on.doc",
        "calendar", "clock", "bell", "bell.fill", "envelope", "message", "phone", "person", "person.2", "checkmark", "checkmark.circle", "xmark.circle",
        "plus", "minus", "magnifyingglass", "pin", "location", "map", "car", "airplane", "cart", "creditcard", "lock", "key", "wifi", "antenna.radiowaves.left.and.right"
    ]
    var body: some View {
        Section(title) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(symbols, id: \.self) { symbol in
                    Button { if selection != symbol { selection = symbol; model.feedback(.selection) } } label: {
                        Image(systemName: symbol).font(.body.weight(.medium)).frame(maxWidth: .infinity).frame(height: 42)
                            .foregroundStyle(selection == symbol ? Color.accentColor : .primary)
                            .background(selection == symbol ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selection == symbol ? Color.accentColor.opacity(0.45) : .clear, lineWidth: 1.5))
                    }.buttonStyle(.plain).accessibilityLabel("Use \(symbol) icon").accessibilityAddTraits(selection == symbol ? .isSelected : [])
                }
            }
        }
    }
}
struct CatalogIcon: View {
    let app: AppEntry
    @EnvironmentObject private var model: PhoneModel
    var body: some View {
        Group {
            if let version = app.iconVersion { RemoteIcon(source: .app(version), store: model.images, fallback: "app").id(version) }
            else { Image(systemName: "app").font(.title2).foregroundStyle(.secondary) }
        }.frame(width: 36, height: 36).accessibilityHidden(true)
    }
}
