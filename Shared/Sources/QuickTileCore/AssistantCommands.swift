import Foundation

/// Catalogs and observed state from the paired Mac. Parsing never discovers or launches apps.
public struct AssistantCommandContext: Sendable {
    public var apps: [AppEntry]
    public var shortcuts: [ShortcutEntry]
    public var controls: ControlState?
    public var playback: [PlaybackSnapshot]
    public var frontmostBundleID: String?
    public init(apps: [AppEntry] = [], shortcuts: [ShortcutEntry] = [], controls: ControlState? = nil,
                playback: [PlaybackSnapshot] = [], frontmostBundleID: String? = nil) {
        self.apps = apps; self.shortcuts = shortcuts; self.controls = controls
        self.playback = playback; self.frontmostBundleID = frontmostBundleID
    }
}

/// A single existing action plus explicit state-setting intent. No script or model-created ID.
/// Executors must refresh state before toggle-backed intents and confirm control readback.
public struct AssistantCommandPlan: Codable, Equatable, Sendable {
    public let title: String
    public let symbol: String
    public let action: DeckAction
    public let targetBundleID: String?
    public let controlValue: Double?
    public let displayID: UInt32?
    public let desiredMuted: Bool?
    public let desiredPlayback: PlaybackState?
    public let desiredDarkMode: Bool?
    public init(title: String, symbol: String, action: DeckAction, targetBundleID: String? = nil,
                controlValue: Double? = nil, displayID: UInt32? = nil, desiredMuted: Bool? = nil,
                desiredPlayback: PlaybackState? = nil, desiredDarkMode: Bool? = nil) {
        self.title = title; self.symbol = symbol; self.action = action; self.targetBundleID = targetBundleID
        self.controlValue = controlValue; self.displayID = displayID; self.desiredMuted = desiredMuted
        self.desiredPlayback = desiredPlayback; self.desiredDarkMode = desiredDarkMode
    }
}

public enum AssistantCommandResolution: Equatable, Sendable {
    case plan(AssistantCommandPlan)
    case choices(prompt: String, plans: [AssistantCommandPlan])
    case unsupported(String)
}

/// Deterministic English canonical-command validation, suitable after model transcription/planning.
/// Supports one catalog app/Shortcut, an explicit HTTPS URL, percentages, mute, media, Mac system
/// actions, or an existing preset named "ACTION in APP". It never interprets shell, arbitrary
/// settings, compound commands, or an inferred website. Relative controls use percentage points
/// (10 by default), require observed state, and clamp to 0...100. App versions are never guessed.
public enum AssistantCommandParser {
    public static func parse(_ text: String, context: AssistantCommandContext = .init()) -> AssistantCommandResolution {
        var command = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, command.count <= 512,
              !command.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return .unsupported("Use one short command, such as Open Safari or Set volume to 50 percent.")
        }
        for prefix in ["please ", "could you ", "can you "] {
            if command.lowercased().hasPrefix(prefix) { command.removeFirst(prefix.count) }
        }
        let key = normalized(command)

        if let groups = captures(#"^(?:open(?: website)?|launch website|visit|go to)\s+(.+)$"#, command),
           groups[0].contains(":") || command.lowercased().contains("website") || command.lowercased().hasPrefix("visit ") || command.lowercased().hasPrefix("go to ") {
            return website(groups[0])
        }
        if command.lowercased().hasPrefix("https://") { return website(command) }

        if let result = control(command, context: context) { return result }
        if ["mute", "mute audio", "mute volume", "mute sound", "mute the mac", "mute my mac"].contains(key) {
            return .plan(.init(title: "Mute", symbol: "speaker.slash.fill", action: .volume(.mute), desiredMuted: true))
        }
        if ["unmute", "unmute audio", "unmute volume", "unmute sound", "unmute the mac", "unmute my mac"].contains(key) {
            return .plan(.init(title: "Unmute", symbol: "speaker.wave.2.fill", action: .volume(.mute), desiredMuted: false))
        }

        let systems: [(SystemCommand, [String], String)] = [
            (.lock, ["lock", "lock screen", "lock the screen", "lock mac", "lock my mac", "lock the mac"], "Lock Mac"),
            (.sleepDisplay, ["sleep display", "sleep screen", "turn off screen", "turn off the screen", "turn off display"], "Sleep display"),
            (.showDesktop, ["show desktop", "show the desktop"], "Show desktop"),
            (.darkMode, ["toggle appearance", "toggle dark mode", "toggle light mode"], "Toggle appearance"),
            (.screenshot, ["screenshot", "take screenshot", "take a screenshot", "capture screen", "capture the screen"], "Screenshot"),
            (.screenshotArea, ["screenshot area", "capture area", "capture an area", "take an area screenshot"], "Capture area")
        ]
        for (system, phrases, title) in systems where phrases.contains(key) {
            let action = DeckAction.system(system)
            return .plan(.init(title: title, symbol: action.fixedSymbol ?? "desktopcomputer", action: action))
        }
        let darkOn = ["enable dark mode", "turn on dark mode", "set dark mode on", "set appearance to dark", "switch to dark mode"]
        let darkOff = ["disable dark mode", "turn off dark mode", "set dark mode off", "set appearance to light", "switch to light mode", "enable light mode"]
        if darkOn.contains(key) || darkOff.contains(key) {
            let dark = darkOn.contains(key)
            return .plan(.init(title: dark ? "Use dark appearance" : "Use light appearance", symbol: "circle.lefthalf.filled",
                               action: .system(.darkMode), desiredDarkMode: dark))
        }

        if let groups = captures(#"^(?:run|start)\s+(?:the\s+)?(?:apple\s+)?shortcut\s+(.+)$"#, command) {
            return shortcut(groups[0], context: context)
        }
        if let result = media(command, context: context) { return result }
        if let groups = captures(#"^(.+?)\s+(?:in|using)\s+(.+)$"#, command) {
            return preset(groups[0], appQuery: groups[1], context: context)
        }
        if let groups = captures(#"^(?:open|launch)\s+(?:the\s+)?(?:app\s+)?(.+)$"#, command) {
            return app(groups[0], context: context)
        }
        return .unsupported("Try an app, a full HTTPS website, a named Apple Shortcut, volume, brightness, playback, or a supported Mac control. Shell commands and arbitrary settings are not supported.")
    }

    private static func website(_ query: String) -> AssistantCommandResolution {
        guard let url = try? Validation.website(query), url.scheme?.lowercased() == "https" else {
            return .unsupported("Give the full https:// address without spaces or a username/password. I cannot guess a website or private URL.")
        }
        return .plan(.init(title: "Open \(url.host ?? "website")", symbol: "globe", action: .website(url: query)))
    }

    private static func control(_ command: String, context: AssistantCommandContext) -> AssistantCommandResolution? {
        var kind: ControlKind
        var amount: Double
        var relative = false
        if let groups = captures(#"^(increase|raise|decrease|lower|reduce)\s+(?:the\s+)?(volume|brightness)(?:\s+by\s+(.+))?$"#, command) {
            kind = groups[1].lowercased() == "volume" ? .volume : .brightness
            guard let percent = groups[2].isEmpty ? 10 : percentage(groups[2]), (0...100).contains(percent) else {
                return .unsupported("Use a change between 0 and 100 percentage points.")
            }
            amount = ["increase", "raise"].contains(groups[0].lowercased()) ? percent : -percent
            relative = true
        } else if let groups = captures(#"^(?:turn\s+)?(?:the\s+)?(volume|brightness)\s+(up|down)(?:\s+by\s+(.+))?$"#, command) {
            kind = groups[0].lowercased() == "volume" ? .volume : .brightness
            guard let percent = groups[2].isEmpty ? 10 : percentage(groups[2]), (0...100).contains(percent) else {
                return .unsupported("Use a change between 0 and 100 percentage points.")
            }
            amount = groups[1].lowercased() == "up" ? percent : -percent
            relative = true
        } else if let groups = captures(#"^(?:(?:set|change|turn)\s+)?(?:the\s+)?(volume|brightness)(?:\s+(?:to|at))?\s+(.+)$"#, command) {
            kind = groups[0].lowercased() == "volume" ? .volume : .brightness
            guard let percent = percentage(groups[1]), (0...100).contains(percent) else {
                return .unsupported("Set \(kind.rawValue) to a number from 0 to 100 percent.")
            }
            amount = percent
        } else { return nil }

        if relative {
            let current = kind == .volume ? context.controls?.volume : context.controls?.brightness
            guard let current, current.isFinite, (0...1).contains(current) else {
                return .unsupported("Refresh the Mac's \(kind.rawValue) first, or give an absolute percentage.")
            }
            amount = min(100, max(0, current * 100 + amount))
        }
        if kind == .brightness, context.controls?.displayID == nil {
            return .unsupported("Choose a supported Mac display and refresh its brightness first.")
        }
        let action = DeckAction.dial(kind)
        return .plan(.init(title: "Set \(kind.rawValue) to \(formatted(amount))%", symbol: action.fixedSymbol ?? "slider.horizontal.3",
                           action: action, controlValue: amount / 100, displayID: kind == .brightness ? context.controls?.displayID : nil))
    }

    private static func app(_ query: String, context: AssistantCommandContext) -> AssistantCommandResolution {
        let matches = matchedApps(query, context: context)
        guard !matches.isEmpty else { return .unsupported("No installed Mac app matches “\(query)”. Choose one from the Mac catalog.") }
        return resolve(matches.map { entry in
            .init(title: "Open \(entry.name)", symbol: AppProfiles.profile(bundleID: entry.id)?.symbol ?? "app",
                  action: .launchApp(bundleID: entry.id), targetBundleID: entry.id)
        }, prompt: "Which Mac app did you mean?")
    }

    private static func shortcut(_ query: String, context: AssistantCommandContext) -> AssistantCommandResolution {
        let query = unquoted(query)
        let valid = context.shortcuts.filter { UUID(uuidString: $0.id) != nil && !$0.name.isEmpty }
        let exact = valid.filter { normalized($0.name) == normalized(query) }
        let matches = (exact.isEmpty ? valid.filter { nameScore(query, $0.name) > 0 } : exact)
            .sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
        var seen = Set<String>()
        let plans: [AssistantCommandPlan] = matches.filter { seen.insert($0.id).inserted }.map {
            .init(title: "Run \($0.name)", symbol: "square.stack.3d.up", action: .shortcut(identifier: $0.id))
        }
        guard !plans.isEmpty else { return .unsupported("No Apple Shortcut matches “\(query)” in the Mac catalog. Refresh Shortcuts or choose its exact name.") }
        return resolve(plans, prompt: "Which Apple Shortcut did you mean?")
    }

    private static func media(_ command: String, context: AssistantCommandContext) -> AssistantCommandResolution? {
        guard let groups = captures(#"^(play pause|toggle playback|toggle play pause|resume|play|pause|next track|skip track|next|previous track|previous|skip back)(?:\s+(?:in\s+|on\s+)?(.+))?$"#, command) else { return nil }
        let verb = normalized(groups[0]), target = normalized(groups[1])
        let player: MediaPlayer?
        switch target {
        case "", "music", "playback", "audio", "the music", "mac playback": player = nil
        case "spotify": player = .spotify
        case "apple music": player = .music
        default:
            if command.lowercased().contains(" in ") { return nil } // May be an app-specific preset.
            return .unsupported("Choose Mac playback, Spotify, or Apple Music. I cannot send playback keys to an arbitrary app.")
        }
        if let player, !context.apps.contains(where: { $0.id == player.rawValue }) {
            return .unsupported("\(player.title) is not in the installed Mac catalog.")
        }
        let mediaCommand: MediaCommand = ["next", "next track", "skip track"].contains(verb) ? .next
            : ["previous", "previous track", "skip back"].contains(verb) ? .previous : .playPause
        let desired: PlaybackState? = ["play", "resume"].contains(verb) ? .playing : verb == "pause" ? .paused : nil
        let targetID = player?.rawValue ?? "system"
        if desired != nil, player == nil,
           !context.playback.contains(where: { $0.target == targetID && $0.state != .unknown }) {
            return .unsupported("Mac playback state is unknown. Say Toggle playback, or choose Spotify or Apple Music explicitly.")
        }
        let title = mediaCommand == .next ? "Next track" : mediaCommand == .previous ? "Previous track"
            : desired == .playing ? "Play" : desired == .paused ? "Pause" : "Toggle playback"
        let action = DeckAction.media(mediaCommand)
        return .plan(.init(title: title + (player.map { " in \($0.title)" } ?? ""), symbol: action.fixedSymbol ?? "playpause.fill",
                           action: action, targetBundleID: player?.rawValue, desiredPlayback: desired))
    }

    private static func preset(_ query: String, appQuery: String, context: AssistantCommandContext) -> AssistantCommandResolution {
        var query = normalized(query)
        if query.hasPrefix("run ") { query.removeFirst(4) }
        if query.hasPrefix("perform ") { query.removeFirst(8) }
        let apps = matchedApps(appQuery, context: context)
        guard !apps.isEmpty else { return .unsupported("Choose an installed Mac app for this action.") }
        var plans: [AssistantCommandPlan] = []
        for app in apps {
            let profile = AppProfiles.profile(bundleID: app.id)
            let matches = ActionLibrary.presets.filter { preset in
                let sameApp = preset.bundleID == app.id || profile?.matches(preset.bundleID) == true
                let identifier = normalized(preset.id.split(separator: ".").last.map(String.init) ?? "")
                return sameApp && (normalized(preset.title) == query || identifier == query)
            }
            for preset in matches {
                plans.append(.init(title: "\(preset.title) in \(app.name)", symbol: preset.symbol,
                                   action: .preset(preset.id), targetBundleID: app.id))
            }
            // Everyday keys still need an explicit installed app, rather than incidental focus.
            for item in ActionLibrary.actions where item.category == .editing && normalized(item.title) == query {
                guard case .keyboard(var shortcut) = item.action else { continue }
                shortcut.targetBundleID = app.id
                if !plans.contains(where: { $0.targetBundleID == app.id }) {
                    plans.append(.init(title: "\(item.title) in \(app.name)", symbol: item.symbol,
                                       action: .keyboard(shortcut), targetBundleID: app.id))
                }
            }
        }
        guard !plans.isEmpty else { return .unsupported("That action is not in QuickTile's mappings for this app. Choose an existing action or Apple Shortcut.") }
        return resolve(plans, prompt: "Which app/action did you mean? Vendor mappings still depend on the app's keymap and focused panel.")
    }

    private static func matchedApps(_ query: String, context: AssistantCommandContext) -> [AppEntry] {
        let query = unquoted(query)
        var scored: [(AppEntry, Int)] = []
        for app in context.apps where (try? Validation.identifier(app.id)) != nil && !app.name.isEmpty {
            var aliases = [app.name, app.id]
            if let profile = AppProfiles.profile(bundleID: app.id) {
                aliases += [profile.id, profile.title]
                if profile.id == "vscode" { aliases.append("Visual Studio Code") }
                if profile.id == "finalcut" { aliases.append("FCP") }
                if profile.id == "resolve" { aliases.append("Resolve") }
                aliases += PresetBoards.boards.filter { $0.profileID == profile.id }.map(\.title)
            }
            let score = aliases.map { nameScore(query, $0) }.max() ?? 0
            if score > 0 { scored.append((app, score)) }
        }
        let exact = scored.filter { $0.1 == 4 }
        let matches = exact.isEmpty ? scored : exact
        var seen = Set<String>()
        return matches.map(\.0).sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
            .filter { seen.insert($0.id).inserted }
    }

    private static func resolve(_ plans: [AssistantCommandPlan], prompt: String) -> AssistantCommandResolution {
        plans.count == 1 ? .plan(plans[0]) : .choices(prompt: prompt, plans: plans)
    }
    private static func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }.joined()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    private static func unquoted(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
    }
    private static func nameScore(_ query: String, _ candidate: String) -> Int {
        let query = normalized(query), candidate = normalized(candidate)
        let compact = query.replacingOccurrences(of: " ", with: "")
        let other = candidate.replacingOccurrences(of: " ", with: "")
        guard !compact.isEmpty else { return 0 }
        if compact == other { return 4 }
        guard compact.count >= 3 else { return 0 }
        if candidate.contains(query) || other.hasPrefix(compact) { return 2 }
        guard compact.count >= 5, abs(compact.count - other.count) <= (compact.count >= 8 ? 2 : 1) else { return 0 }
        return editDistance(compact, other) <= (compact.count >= 8 ? 2 : 1) ? 1 : 0
    }
    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs), right = Array(rhs)
        var previous = Array(0...right.count)
        for (index, character) in left.enumerated() {
            var current = [index + 1]
            for (column, other) in right.enumerated() {
                current.append(min(current[column] + 1, previous[column + 1] + 1, previous[column] + (character == other ? 0 : 1)))
            }
            previous = current
        }
        return previous.last ?? left.count
    }
    private static func percentage(_ text: String) -> Double? {
        var value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["percentage points", "per cent", "percent", "%"] where value.hasSuffix(suffix) {
            value = String(value.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        if let number = Double(value), number.isFinite { return number }
        let words = normalized(value).split(separator: " ").map(String.init)
        let units = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
        let tens = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
        if words == ["one", "hundred"] { return 100 }
        if words.count == 1, let unit = units.firstIndex(of: words[0]) { return Double(unit) }
        if (1...2).contains(words.count), let ten = tens[words[0]] {
            if words.count == 1 { return Double(ten) }
            if let unit = units.firstIndex(of: words[1]), (1...9).contains(unit) { return Double(ten + unit) }
        }
        return nil
    }
    private static func formatted(_ value: Double) -> String {
        String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
