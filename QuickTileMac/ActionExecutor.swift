import AppKit
import ApplicationServices
import QuickTileCore

@MainActor final class ActionExecutor {
    let catalog: Catalog
    let agents: AgentStatusStore
    let players = MediaPlayerControl()
    private var keyboardBusy = false
    private var sequenceBusy = false
    var preferredBundleIDs: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "preferredAppProfiles") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "preferredAppProfiles") }
    }
    private var baseCapabilities: Capabilities {
        var value = Capabilities(keyboard: AXIsProcessTrusted(), music: false,
                                 volume: VolumeControl().supportsVolume, mute: VolumeControl().supportsMute,
                                 notes: ["Media controls send the Mac’s media keys to the current player.",
                                          "Keyboard events use physical ANSI key positions. Secure input or an app may ignore them."])
        value.controlsVersion = 1
        value.mediaKeys = AXIsProcessTrusted()
        value.sequenceVersion = 1
        value.features = ["sequences.v1", "structured-results.v1", "display-selection.v1", "control-mute.v1", "frontmost-app.v1", "playback-state.v1", "media-player-adapters.v1", "agent-health.v1"]
        value.brightness = BrightnessControl.shared.snapshot().brightness != nil
        value.frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // Media-key delivery cannot reveal the active player’s playback state.
        value.playback = [.init(target: "system", state: .unknown)] + players.snapshots
        return value
    }
    init(catalog: Catalog, agents: AgentStatusStore) { self.catalog = catalog; self.agents = agents }
    var capabilities: Capabilities {
        var value = baseCapabilities
        value.keyboard = AXIsProcessTrusted()
        value.mediaKeys = AXIsProcessTrusted()
        value.agents = agents.snapshots
        value.agentSources = AgentProvider.allCases.flatMap { provider in [AgentSource.desktop, .terminal].map { agents.snapshot(provider, source: $0) } }
        return value
    }
    func executeCommand(_ command: Command, authorized: @escaping () -> Bool, progress: @escaping (SequenceProgress) -> Void = { _ in }) async throws -> ActionResult {
        if case .media(let control) = command.action, let target = command.targetBundleID {
            guard let player = MediaPlayer(rawValue: target) else { throw QuickTileError.invalid("Choose a supported media player.") }
            guard authorized() else { throw QuickTileError.unauthorized }
            try await players.execute(control, player: player)
            return .init(.completed, "Sent \(player.title) control", outcome: .commandSent)
        }
        if case .sequence(let sequence) = command.action {
            guard !sequenceBusy, !keyboardBusy else { throw QuickTileError.failed("Another keyboard workflow is running.") }
            try sequence.validate()
            sequenceBusy = true; defer { sequenceBusy = false }
            let started = Date()
            for (index, step) in sequence.steps.enumerated() {
                try Task.checkCancellation()
                guard authorized() else { throw QuickTileError.unauthorized }
                let remaining = ActionSequence.maximumDuration - Date().timeIntervalSince(started)
                guard remaining > 0 else { throw QuickTileError.timeout }
                progress(.init(stepIndex: index, stepCount: sequence.steps.count, title: step.title))
                if case .wait(let seconds) = step {
                    guard remaining >= seconds else { throw QuickTileError.timeout }
                    try await Task.sleep(for: .seconds(seconds))
                } else if let action = step.action {
                    _ = try await execute(action, authorized: authorized, withinSequence: true, deadline: started.addingTimeInterval(ActionSequence.maximumDuration))
                }
            }
            return .init(.completed, "Finished sequence", outcome: .sequenceCompleted)
        }
        var action = command.action
        if case .agent = action, let target = command.targetBundleID { action = .launchApp(bundleID: target) }
        if let configured = command.configuredShortcut {
            guard case .preset = action else { throw QuickTileError.invalid("Only preset tiles accept customized mappings.") }
            var key = configured
            if let target = command.targetBundleID { key.targetBundleID = target }
            guard key.targetBundleID != nil else { throw QuickTileError.invalid("Choose a target app for this mapping.") }
            action = .keyboard(key)
        } else if case .preset(let id) = action, let target = command.targetBundleID {
            guard let preset = ActionLibrary.preset(id: id), AppProfiles.profile(bundleID: preset.bundleID)?.matches(target) == true,
                  var key = preset.shortcut else { throw QuickTileError.invalid("Choose a matching installed app for this preset.") }
            key.targetBundleID = target; action = .keyboard(key)
        }
        let message = try await execute(action, authorized: authorized)
        let outcome: ActionOutcome
        switch action {
        case .launchApp, .website, .agent: outcome = .opened
        case .keyboard, .preset, .media, .music: outcome = .commandSent
        case .shortcut: outcome = .shortcutCompleted
        case .system(let command): outcome = [.lock, .showDesktop, .screenshot, .screenshotArea].contains(command) ? .commandSent : .stateChanged
        default: outcome = .stateChanged
        }
        return .init(.completed, message, outcome: outcome)
    }
    /// Validate every step before the first effect, then reserve keyboard execution for this request.
    func executeAssistant(_ plans: [AssistantCommandPlan], authorized: @escaping () -> Bool) async throws -> ActionResult {
        guard !sequenceBusy, !keyboardBusy else { throw QuickTileError.failed("Another keyboard workflow is running.") }
        try AssistantPlanValidation.validate(plans, capabilities: capabilities, apps: catalog.apps, shortcuts: catalog.shortcuts)
        sequenceBusy = true; defer { sequenceBusy = false }
        let deadline = Date().addingTimeInterval(300)
        var final: ActionResult = .init(.completed, "Finished", outcome: .stateChanged)
        var completed = 0
        do {
            for plan in plans {
                try Task.checkCancellation()
                guard authorized() else { throw QuickTileError.unauthorized }
                guard Date() < deadline else { throw QuickTileError.timeout }
                if let bundle = plan.quitBundleID {
                    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
                    guard apps.allSatisfy({ $0.terminate() }) else { throw QuickTileError.failed("macOS could not request that app to quit.") }
                    final = .init(.completed, apps.isEmpty ? "Already closed" : "Requested \(plan.title)", outcome: .commandSent)
                } else if let value = plan.controlValue, case .dial(let kind) = plan.action {
                    if kind == .volume { try VolumeControl().setDialLevel(value) }
                    else if let display = plan.displayID { try BrightnessControl.shared.set(value, displayID: display) }
                    final = .init(.completed, plan.title, outcome: .stateChanged)
                } else if let muted = plan.desiredMuted {
                    let audio = VolumeControl()
                    guard let current = audio.isMuted() else { throw QuickTileError.unsupported("This output needs its hardware mute control.") }
                    if current != muted { try audio.execute(.mute) }
                    final = .init(.completed, muted ? "Muted" : "Unmuted", outcome: .stateChanged)
                } else if let state = plan.desiredPlayback {
                    guard let target = plan.targetBundleID, let player = MediaPlayer(rawValue: target) else { throw QuickTileError.unsupported("Choose Spotify or Apple Music for explicit playback state.") }
                    try await players.setPlayback(state, player: player)
                    final = .init(.completed, "Sent \(plan.title)", outcome: .commandSent)
                } else if let dark = plan.desiredDarkMode {
                    let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to " + (dark ? "true" : "false")
                    let output = try await ProcessJob().run(executable: "/usr/bin/osascript", arguments: ["-e", script], timeout: 20)
                    guard output.status == 0 else { throw QuickTileError.failed("Allow Automation on your Mac.") }
                    let observed = try await ProcessJob().run(executable: "/usr/bin/osascript", arguments: ["-e", "tell application \"System Events\" to tell appearance preferences to get dark mode"], timeout: 5)
                    guard observed.status == 0, observed.text.trimmingCharacters(in: .whitespacesAndNewlines) == (dark ? "true" : "false") else { throw QuickTileError.failed("The Mac did not confirm its appearance.") }
                    final = .init(.completed, dark ? "Set dark appearance" : "Set light appearance", outcome: .stateChanged)
                } else if case .media(let command) = plan.action, let target = plan.targetBundleID, let player = MediaPlayer(rawValue: target) {
                    try await players.execute(command, player: player)
                    final = .init(.completed, "Sent \(plan.title)", outcome: .commandSent)
                } else {
                    var action = plan.action
                    if case .preset(let id) = action, let target = plan.targetBundleID, var keys = ActionLibrary.preset(id: id)?.shortcut {
                        keys.targetBundleID = target; action = .keyboard(keys)
                    }
                    _ = try await execute(action, authorized: authorized, withinSequence: true, deadline: deadline)
                    let prefix: String
                    let outcome: ActionOutcome
                    switch plan.action {
                    case .launchApp, .website: prefix = "Opened "; outcome = .opened
                    case .shortcut: prefix = "Ran "; outcome = .shortcutCompleted
                    default: prefix = "Sent "; outcome = .commandSent
                    }
                    let name = plan.title.replacingOccurrences(of: "^(Open|Run) ", with: "", options: .regularExpression)
                    final = .init(.completed, prefix + name, outcome: outcome)
                }
                completed += 1
            }
        } catch {
            if completed > 0 { throw QuickTileError.failed("Stopped after \(completed) of \(plans.count) actions. \(error.localizedDescription)") }
            throw error
        }
        return plans.count == 1 ? final : .init(.completed, "Finished \(plans.count) actions", outcome: .sequenceCompleted)
    }
    func execute(_ action: DeckAction, authorized: () -> Bool, withinSequence: Bool = false, deadline: Date? = nil) async throws -> String {
        try action.validate()
        try Task.checkCancellation()
        guard authorized() else { throw QuickTileError.unauthorized }
        switch action {
        case .assistant: throw QuickTileError.unsupported("Use the assistant request interface.")
        case .sequence: throw QuickTileError.unsupported("Use the sequence command interface.")
        case .timer: throw QuickTileError.unsupported("Timers run on your iPhone.")
        case .agent(let provider):
            if let id = provider.bundleIDs.first(where: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }) {
                _ = try await activate(id, requireForeground: false)
            } else {
                _ = try await activate("com.apple.Terminal", requireForeground: false)
            }
            return "Opened"
        case .dial: throw QuickTileError.unsupported("Turn this dial on your iPhone to adjust it.")
        case .launchApp(let id):
            _ = try await activate(id, requireForeground: withinSequence)
            return "Opened"
        case .website(let text):
            let url = try Validation.website(text)
            guard NSWorkspace.shared.open(url) else { throw QuickTileError.failed("macOS could not open this URL in the default browser.") }
            return "Opened"
        case .keyboard(let shortcut):
            guard !keyboardBusy, !sequenceBusy || withinSequence else { throw QuickTileError.failed("Another keyboard workflow is running.") }
            keyboardBusy = true
            defer { keyboardBusy = false }
            guard AXIsProcessTrusted() else {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
                throw QuickTileError.failed("Enable QuickTileMac in System Settings → Privacy & Security → Accessibility, then try again.")
            }
            if let target = shortcut.targetBundleID {
                let app = try await activate(target)
                let deadline = Date().addingTimeInterval(2)
                while NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier, Date() < deadline {
                    try await Task.sleep(for: .milliseconds(40))
                }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { throw QuickTileError.failed("The target app could not become foreground. No keys were sent.") }
            }
            try Task.checkCancellation()
            guard authorized(), AXIsProcessTrusted() else { throw QuickTileError.unauthorized }
            try post(shortcut)
            return "Sent keys"
        case .volume(let command): try VolumeControl().execute(command); return "Updated volume"
        case .media(let command), .music(let command):
            guard AXIsProcessTrusted() else { throw QuickTileError.failed("Allow QuickTileMac in Accessibility on your Mac.") }
            let events = try Self.mediaEvents(command).compactMap(\.cgEvent)
            guard events.count == 2 else { throw QuickTileError.failed("Could not send media key.") }
            events.forEach { $0.post(tap: .cghidEventTap) }
            return "Sent"
        case .preset(let id):
            guard let preset = ActionLibrary.preset(id: id), var shortcut = preset.shortcut else { throw QuickTileError.unsupported("Edit this tile to choose a shortcut.") }
            let profile = AppProfiles.profile(bundleID: preset.bundleID)
            guard let app = AppProfiles.resolve(bundleID: preset.bundleID, apps: catalog.apps, preferredBundleID: profile.flatMap { preferredBundleIDs[$0.id] }) else {
                throw QuickTileError.failed("\(preset.appName) is not installed. Refresh the Mac catalog and choose a target app.")
            }
            shortcut.targetBundleID = app.id
            return try await execute(.keyboard(shortcut), authorized: authorized, withinSequence: withinSequence, deadline: deadline)
        case .system(let command):
            let shortcut: KeyboardShortcut
            switch command {
            case .lock: shortcut = .init(key: "q", modifiers: [.control, .command])
            case .showDesktop: shortcut = .init(key: "f11")
            case .screenshot: shortcut = .init(key: "3", modifiers: [.command, .shift])
            case .screenshotArea: shortcut = .init(key: "4", modifiers: [.command, .shift])
            case .sleepDisplay, .darkMode:
                let output = try await ProcessJob().run(executable: command == .sleepDisplay ? "/usr/bin/pmset" : "/usr/bin/osascript", arguments: command == .sleepDisplay ? ["displaysleepnow"] : ["-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"], timeout: 20)
                guard output.status == 0 else { throw QuickTileError.failed("Check the Mac for a permission request.") }
                return "Updated"
            }
            return try await execute(.keyboard(shortcut), authorized: authorized, withinSequence: withinSequence, deadline: deadline)
        case .shortcut(let id):
            guard catalog.shortcuts.contains(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else { throw QuickTileError.failed("This shortcut is missing. Refresh the Mac catalog and select it again.") }
            let timeout = min(300, deadline?.timeIntervalSinceNow ?? 300)
            guard timeout > 0 else { throw QuickTileError.timeout }
            let output = try await ProcessJob().run(executable: "/usr/bin/shortcuts", arguments: ["run", id], timeout: timeout)
            guard output.status == 0 else { throw QuickTileError.failed("Shortcut failed. Check the Mac for a permission or input prompt. \(output.error.prefix(400))") }
            return "Ran shortcut"
        }
    }
    static func mediaEvents(_ command: MediaCommand) throws -> [NSEvent] {
        let code: Int = switch command { case .playPause: 16; case .next: 17; case .previous: 18 }
        let events = [0xA, 0xB].compactMap { state in
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)), timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil, subtype: 8, data1: (code << 16) | (state << 8), data2: -1)
        }
        guard events.count == 2 else { throw QuickTileError.failed("Could not create media key.") }
        return events
    }
    private func activate(_ id: String, requireForeground: Bool = true) async throws -> NSRunningApplication {
        let profile = AppProfiles.profile(bundleID: id)
        let resolved = catalog.url(for: id) != nil ? id : (AppProfiles.resolve(bundleID: id, apps: catalog.apps, preferredBundleID: profile.flatMap { preferredBundleIDs[$0.id] })?.id ?? id)
        guard let url = catalog.url(for: resolved) else { throw QuickTileError.failed("This app is no longer installed. Refresh the catalog and edit the tile.") }
        try Self.validateAppIdentity(url, expected: resolved)
        let config = NSWorkspace.OpenConfiguration(); config.activates = true
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        guard app.bundleIdentifier == resolved else { throw QuickTileError.failed("The application changed. Refresh the catalog and choose it again. No keys were sent.") }
        _ = app.unhide()
        _ = app.activate(options: [.activateAllWindows])
        // Successful app opening and keyboard focus are separate outcomes.
        // macOS may decline foreground activation for a background controller.
        // Targeted keys and sequence activation always require confirmed focus.
        guard requireForeground else { return app }
        let deadline = Date().addingTimeInterval(2)
        while NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier, Date() < deadline {
            try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(40))
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { throw QuickTileError.failed("The target app could not become foreground. No keys were sent.") }
        return app
    }
    static func validateAppIdentity(_ url: URL, expected: String) throws {
        guard Bundle(url: url)?.bundleIdentifier == expected else { throw QuickTileError.failed("The application changed. Refresh the catalog and choose it again. No keys were sent.") }
    }
    private func post(_ shortcut: KeyboardShortcut) throws {
        guard let code = KeyboardShortcut.keyCodes[shortcut.key], let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { throw QuickTileError.failed("macOS could not create key events.") }
        let mapping: [KeyModifier: (UInt16, CGEventFlags)] = [.command:(55,.maskCommand), .option:(58,.maskAlternate), .control:(59,.maskControl), .shift:(56,.maskShift)]
        // Allocate every release before posting any press. No suspension/cancellation point while keys are down.
        let modifiers = try shortcut.modifiers.map { modifier -> (CGEvent, CGEvent, CGEventFlags) in
            let (key, flag) = mapping[modifier]!
            guard let press = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true), let release = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { throw QuickTileError.failed("macOS could not create modifier events.") }
            return (press, release, flag)
        }
        var flags: CGEventFlags = []
        defer {
            up.flags = flags; up.post(tap: .cghidEventTap)
            for (_, release, flag) in modifiers.reversed() { flags.remove(flag); release.flags = flags; release.post(tap: .cghidEventTap) }
        }
        for (press, _, flag) in modifiers { flags.insert(flag); press.flags = flags; press.post(tap: .cghidEventTap) }
        down.flags = flags; down.post(tap: .cghidEventTap)
    }
}
