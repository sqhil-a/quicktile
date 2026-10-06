import Foundation
import CryptoKit
import QuickTileCore

/// Local lifecycle metadata and bounded pending request details. Installation is always an explicit settings action.
@MainActor final class AgentStatusStore: ObservableObject {
    @Published private(set) var snapshots: [AgentSnapshot] = AgentProvider.allCases.map { .init(provider: $0, phase: .unavailable, health: .notConfigured) }
    @Published private(set) var enabled = false
    @Published private(set) var error: String?
    @Published private(set) var trackingIssue: String?
    @Published private(set) var repliesConnected = false
    private let directory: URL
    private let reader: AgentMetadataReader
    private var events: [AgentEvent] = []
    let controlBridge = CodexControlBridge()
    private var installationIssues: [AgentProvider: String] = [:]
    private var task: Task<Void, Never>?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = base.appendingPathComponent("QuickTile/AgentStatus", isDirectory: true)
        reader = AgentMetadataReader(directory: directory)
        enabled = FileManager.default.fileExists(atPath: directory.appendingPathComponent("enabled").path)
        if enabled {
            installationIssues = AgentTrackingInstallation.issues(directory: directory)
            trackingIssue = AgentProvider.allCases.compactMap { installationIssues[$0] }.first
        }
        controlBridge.onChange = { [weak self] in self?.refresh() }
        // Never rewrite trusted hook definitions during launch or a software upgrade.
        refresh()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.enabled {
                    self.events = await self.reader.refresh()
                    self.installationIssues = await self.reader.installationIssues()
                    self.trackingIssue = AgentProvider.allCases.compactMap { self.installationIssues[$0] }.first
                }
                self.controlBridge.refresh(enabled: self.enabled)
                self.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    deinit { task?.cancel() }
    func refresh() {
        if repliesConnected != controlBridge.connected { repliesConnected = controlBridge.connected }
        let current = AgentProvider.allCases.map { snapshot($0) }
        if snapshots != current { snapshots = current }
    }
    func snapshot(_ provider: AgentProvider, source: AgentSource = .unknown) -> AgentSnapshot {
        var value = AgentEvent.snapshot(provider: provider, events: events, configured: enabled, source: source)
        if provider == .codex, source == .unknown, controlBridge.connected, !controlBridge.phases.isEmpty {
            let phases = Array(controlBridge.phases.values)
            value.phase = phases.contains(.waiting) ? .waiting : (phases.contains(.running) ? .running : (phases.contains(.unknown) ? .unknown : .idle))
            value.health = .healthy; value.updatedAt = Date(); value.activeSessions = phases.filter { $0 == .running || $0 == .waiting }.count
            return value
        }
        if enabled, installationIssues[provider] != nil {
            // Log-only activity cannot establish approval coverage when hook installation is broken.
            value.phase = .unknown; value.health = .stale; value.activeSessions = 0
        }
        return value
    }
    func requests(_ provider: AgentProvider, source: AgentSource) -> [AgentInputRequest] {
        if provider == .codex, source == .unknown, controlBridge.connected, !controlBridge.requests.isEmpty { return controlBridge.requests }
        return AgentEvent.pendingRequests(provider:provider,events:events,source:source)
    }
    var needsRepair: Bool { enabled && !installationIssues.isEmpty }
    private var helper: URL { directory.appendingPathComponent("QuickTileAgentEvent") }
    private var hookFiles: [(URL, AgentProvider)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [(home.appendingPathComponent(".codex/hooks.json"), .codex), (home.appendingPathComponent(".claude/settings.json"), .claude)]
    }
    @discardableResult func enable() -> Bool {
        error = nil
        do {
            let fm = FileManager.default
            let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/QuickTileAgentEvent")
            guard fm.isExecutableFile(atPath: bundled.path) else {
                throw NSError(domain: "QuickTileAgentStatus", code: 1, userInfo: [NSLocalizedDescriptionKey: "The event helper is missing. Reinstall the Mac companion."])
            }
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let staged = directory.appendingPathComponent("QuickTileAgentEvent-new")
            try? fm.removeItem(at: staged)
            try fm.copyItem(at: bundled, to: staged)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staged.path)
            if fm.fileExists(atPath: helper.path) { _ = try fm.replaceItemAt(helper, withItemAt: staged) }
            else { try fm.moveItem(at: staged, to: helper) }
            try updateHooks(removing: false)
            try Data("enabled".utf8).write(to: directory.appendingPathComponent("enabled"), options: .atomic)
            enabled = true
            installationIssues = AgentTrackingInstallation.issues(directory: directory)
            trackingIssue = AgentProvider.allCases.compactMap { installationIssues[$0] }.first
            refresh(); return true
        } catch { self.error = "Could not set up tracking: \(error.localizedDescription)"; return false }
    }
    @discardableResult func disable() -> Bool {
        error = nil
        do {
            try updateHooks(removing: true)
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("enabled"))
            try? FileManager.default.removeItem(at: helper)
            let files = (try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)) ?? []
            for file in files where file.pathExtension == "json" && (file.lastPathComponent.hasPrefix("codex-") || file.lastPathComponent.hasPrefix("claude-")) {
                try? FileManager.default.removeItem(at:file)
            }
            controlBridge.stop()
            enabled = false; events = []; installationIssues = [:]; trackingIssue = nil; refresh(); return true
        } catch { self.error = "Could not remove tracking hooks: \(error.localizedDescription)"; return false }
    }
    private func updateHooks(removing: Bool) throws {
        let fm = FileManager.default
        // Prepare every edit before writing either provider's configuration.
        let edits = try hookFiles.compactMap { url, provider -> (URL, Data?, Data)? in
            let original = fm.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
            if removing && original == nil { return nil }
            let command = Self.quote(helper.path) + " " + provider.rawValue
            return (url, original, try AgentHookConfiguration.update(original ?? Data("{}".utf8), provider: provider, command: command, removing: removing))
        }
        var completed: [(URL, Data?)] = []
        do {
            for (url, original, updated) in edits {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let original {
                    // Keep one pre-install recovery copy; never overwrite the user's first backup.
                    let backup = directory.appendingPathComponent("\(url.deletingLastPathComponent().lastPathComponent)-original.json")
                    if !fm.fileExists(atPath: backup.path) { try original.write(to: backup, options: .atomic) }
                }
                try updated.write(to: url, options: .atomic)
                completed.append((url, original))
            }
        } catch {
            for (url, original) in completed.reversed() {
                if let original { try? original.write(to: url, options: .atomic) } else { try? fm.removeItem(at: url) }
            }
            throw error
        }
    }
    private static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// Compatibility entrypoint for hooks installed by older companion versions.
    @discardableResult static func handleCommandLine() -> Bool {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--agent-event"), args.indices.contains(index + 1),
              let provider = AgentProvider(rawValue: args[index + 1]) else { return false }
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let name = (try? JSONSerialization.jsonObject(with: input) as? [String: Any])?["hook_event_name"] as? String
        defer { if name == "Stop" { FileHandle.standardOutput.write(Data("{}\n".utf8)) } }
        guard let event = AgentEvent(provider: provider, input: input) else { return true }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("QuickTile/AgentStatus", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let identifier = SHA256.hash(data: Data(event.session.utf8)).map { String(format: "%02x", $0) }.joined()
        let url = directory.appendingPathComponent("\(provider.rawValue)-\(identifier).json")
        var state = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(AgentEvent.self, from: $0) }.map(AgentSessionState.init)
        if state == nil { state = .init(event: event) } else { state?.apply(event) }
        if let state, let data = try? JSONEncoder().encode(state.event) { try? data.write(to: url, options: .atomic) }
        return true
    }
}

/// File IO and JSON parsing stay outside the main actor. Transcripts never leave this reader.
private actor AgentMetadataReader {
    private let directory: URL
    private let codex = CodexActivityReader()
    private var hooks: [URL: (Date, AgentEvent)] = [:]
    init(directory: URL) { self.directory = directory }
    func installationIssues() -> [AgentProvider: String] { AgentTrackingInstallation.issues(directory: directory) }
    func refresh() async -> [AgentEvent] {
        let fm = FileManager.default
        var seen = Set<URL>()
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        for url in files where url.pathExtension == "json" && !url.lastPathComponent.contains("original") {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modified = values.contentModificationDate, (values.fileSize ?? .max) <= 131_072 else { continue }
            seen.insert(url)
            if hooks[url]?.0 == modified { continue }
            guard let data = try? Data(contentsOf: url), let event = try? JSONDecoder().decode(AgentEvent.self, from: data) else { continue }
            hooks[url] = (modified, event)
        }
        hooks = hooks.filter { seen.contains($0.key) }
        return hooks.values.map { $0.1 } + (await codex.refresh())
    }
}

/// Read-only installation checks. These do not inspect or modify vendor trust records.
enum AgentTrackingInstallation {
    static func issues(directory: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AgentProvider: String] {
        var result: [AgentProvider: String] = [:]
        for provider in AgentProvider.allCases {
            let file = home.appendingPathComponent(provider == .codex ? ".codex/hooks.json" : ".claude/settings.json")
            if let problem = issue(directory: directory, hookFile: file, provider: provider) { result[provider] = problem }
        }
        return result
    }
    static func issue(directory: URL, hookFile: URL, provider: AgentProvider) -> String? {
        let helper = directory.appendingPathComponent("QuickTileAgentEvent")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            return "The tracking helper is missing. Repair tracking in Mac settings, then review the Codex hooks."
        }
        guard let values = try? hookFile.resourceValues(forKeys: [.fileSizeKey]), (values.fileSize ?? .max) <= 1_048_576,
              let data = try? Data(contentsOf: hookFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else {
            return "\(provider.title) tracking hooks are missing or unreadable. Repair tracking in Mac settings."
        }
        let quoted = "'" + helper.path.replacingOccurrences(of: "'", with: "'\\''") + "' " + provider.rawValue
        // These lifecycle events distinguish work, approval, completion, and interruption.
        let required = AgentHookConfiguration.requiredEvents(for: provider)
        for event in required {
            let matchers = hooks[event] as? [[String: Any]] ?? []
            let installed = matchers.contains { matcher in
                let pattern = matcher["matcher"] as? String ?? ""
                guard pattern.isEmpty || pattern == "*" else { return false }
                return (matcher["hooks"] as? [[String: Any]] ?? []).contains { handler in
                    handler["type"] as? String == "command" && handler["command"] as? String == quoted
                }
            }
            guard installed else { return "\(provider.title) tracking hooks need repair. Repair tracking in Mac settings, then review updated hooks in the agent."
            }
        }
        return nil
    }
}

/// Bounded, incremental adapter for local Codex logs. The log format is not a supported API.
actor CodexActivityReader {
    private struct Cursor {
        var identity: String
        var session: String
        var source: AgentSource
        var modifiedAt: Date?
        var offset: UInt64 = 0
        var pending = Data()
        var state: AgentSessionState?
    }
    private var cursors: [URL: Cursor] = [:]
    private let root: URL
    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")) { self.root = root }
    private var lastScan = Date.distantPast
    private var urls: [URL] = []
    func refresh() -> [AgentEvent] {
        if Date().timeIntervalSince(lastScan) >= 2 {
            lastScan = Date()
            if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) {
                var recent: [(URL, Date)] = []
                for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                    guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                          values.isRegularFile == true, let date = values.contentModificationDate,
                          Date().timeIntervalSince(date) < 7 * 86400 else { continue }
                    recent.append((url, date))
                }
                urls = recent.sorted { $0.1 > $1.1 }.prefix(128).map(\.0)
                cursors = cursors.filter { urls.contains($0.key) }
            } else { urls = []; cursors = [:] }
        }
        for url in urls { read(url) }
        return cursors.values.compactMap { $0.state?.event }
    }
    private func read(_ url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? UInt64,
              let file = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? file.close() }
        let identity = "\(attributes[.systemFileNumber] ?? "")"
        let modifiedAt = attributes[.modificationDate] as? Date
        var cursor = cursors[url]
        if cursor?.identity != identity || (cursor?.offset ?? 0) > size
            || (cursor?.offset == size && cursor?.modifiedAt != modifiedAt) {
            cursor = nil
        }
        if cursor == nil {
            guard let metadata = header(file), let session = (metadata["session_id"] as? String) ?? (metadata["id"] as? String),
                  !session.isEmpty, session.utf8.count <= 256 else { return }
            if let source = metadata["source"] as? [String: Any], source["subagent"] != nil { return }
            // Cloud/browser conversation metadata is not local Codex activity.
            if ["cloud", "chatgpt", "web"].contains(metadata["source"] as? String ?? "") { return }
            let source = AgentEvent.source(from: metadata["source"])
            cursor = Cursor(identity: identity, session: session, source: source == .unknown ? AgentEvent.source(from: metadata["originator"]) : source)
            let offset = size > 4_194_304 ? size - 4_194_304 : 0
            cursor?.offset = offset
            try? file.seek(toOffset: offset)
            if offset > 0 {
                // Discard the initial partial record at the bounded tail boundary.
                var skip = Data()
                while skip.count < 2_097_152 {
                    guard let chunk = try? file.read(upToCount: 65_536), !chunk.isEmpty else { break }
                    skip.append(chunk)
                    if let newline = skip.firstIndex(of: 10) {
                        cursor?.pending = Data(skip.suffix(from: skip.index(after: newline)))
                        cursor?.offset = (try? file.offset()) ?? size
                        break
                    }
                }
            }
        }
        guard var current = cursor else { return }
        current.modifiedAt = modifiedAt
        try? file.seek(toOffset: current.offset)
        // Limit a poll to four MiB even when a tool produced a huge transcript record.
        let count = min(UInt64(4_194_304), size - current.offset)
        if count > 0, let bytes = try? file.read(upToCount: Int(count)) {
            current.offset += UInt64(bytes.count); current.pending.append(bytes)
        }
        if let lastNewline = current.pending.lastIndex(of: 10) {
            let complete = Data(current.pending.prefix(through: lastNewline))
            current.pending = Data(current.pending.suffix(from: current.pending.index(after: lastNewline)))
            for event in AgentEvent.codexEvents(in: complete, session: current.session, source: current.source) {
                if current.state == nil { current.state = .init(event: event) } else { current.state?.apply(event) }
            }
        }
        if current.pending.count > 2_097_152 { current.pending = Data() }
        cursors[url] = current
    }
    private func header(_ file: FileHandle) -> [String: Any]? {
        var buffer = Data()
        while buffer.count < 2_097_152 {
            guard let chunk = try? file.read(upToCount: min(65_536, 2_097_152 - buffer.count)), !chunk.isEmpty else { break }
            buffer.append(chunk)
            if let newline = buffer.firstIndex(of: 10) {
                guard let json = try? JSONSerialization.jsonObject(with: Data(buffer.prefix(upTo: newline))) as? [String: Any] else { return nil }
                return json["payload"] as? [String: Any]
            }
        }
        return nil
    }
}

/// Attaches to an already-running Codex control socket. Never starts/resumes a thread,
/// replaces its host, changes permissions, or creates another Codex server.
@MainActor final class CodexControlBridge {
    private(set) var requests: [AgentInputRequest] = []
    private(set) var phases: [String: AgentPhase] = [:]
    private(set) var connected = false
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var pending = Data()
    private var requestIDs: [UUID: Any] = [:]
    private var confirmations: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var deadlines: [UUID: Task<Void, Never>] = [:]
    private var lastAttempt = Date.distantPast
    private var testingSend: (([String:Any]) throws -> Void)?
    init(testingSend: (([String:Any]) throws -> Void)? = nil) {
        self.testingSend = testingSend
        if testingSend != nil { connected = true }
    }
    private var counter = 10
    private var readIDs: [Int: String] = [:]
    private var generation = UUID()
    var onChange: (() -> Void)?
    deinit { process?.terminate(); output?.readabilityHandler = nil }

    func refresh(enabled: Bool) {
        guard enabled else { stop(); return }
        if process == nil {
            guard Date().timeIntervalSince(lastAttempt) > 5 else { return }
            lastAttempt = Date()
            let socket = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/app-server-control/app-server-control.sock")
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: socket.path),
                  attributes[.ownerAccountID] as? UInt32 == getuid(), attributes[.type] as? FileAttributeType == .typeSocket else { return }
            let paths = ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", "/Applications/Codex.app/Contents/Resources/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath:$0) }) else { return }
            let child = Process(), stdin = Pipe(), stdout = Pipe()
            child.executableURL = URL(fileURLWithPath:path); child.arguments = ["app-server","proxy","--sock",socket.path]
            child.standardInput = stdin; child.standardOutput = stdout; child.standardError = FileHandle.nullDevice
            let version = UUID(); generation = version
            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let bytes = handle.availableData
                Task { @MainActor [weak self] in
                    guard let self, self.generation == version else { return }
                    if bytes.isEmpty { self.stop() } else { self.receive(bytes) }
                }
            }
            child.terminationHandler = { [weak self] _ in Task { @MainActor in if self?.generation == version { self?.stop() } } }
            do {
                try child.run(); process = child; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
                try send(["id":1,"method":"initialize","params":["clientInfo":["name":"quicktile","version":"1.0"],"capabilities":["experimentalApi":true]]])
            } catch { stop() }
        } else if connected { counter += 1; try? send(["id":counter,"method":"thread/loaded/list"]) }
    }
    private func send(_ object: [String: Any]) throws {
        if let testingSend { try testingSend(object); return }
        guard let input else { throw QuickTileError.failed("Codex’s reply connection is unavailable.") }
        var data = try JSONSerialization.data(withJSONObject:object); data.append(10)
        try input.write(contentsOf:data)
    }
    private func receive(_ bytes: Data) {
        pending.append(bytes)
        guard pending.count <= 1_048_576 else { stop(); return }
        while let newline = pending.firstIndex(of:10) {
            let line = pending.prefix(upTo:newline); pending.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with:line) as? [String:Any] else { continue }
            ingest(object)
        }
    }
    /// Internal protocol reducer also used by deterministic tests. Request content stays in memory.
    func ingest(_ object: [String: Any]) {
        if object["id"] as? Int == 1, object["result"] != nil {
            connected = true; try? send(["method":"initialized"]); onChange?(); return
        }
        if let id = object["id"] as? Int, let result = object["result"] as? [String:Any] {
            if let session = readIDs.removeValue(forKey:id), let thread = result["thread"] as? [String:Any], let status = thread["status"] as? [String:Any] {
                update(session:session,status:status)
            } else if let sessions = result["data"] as? [String] {
                phases = phases.filter { sessions.contains($0.key) }
                for session in sessions.prefix(64) { counter += 1; readIDs[counter] = session; try? send(["id":counter,"method":"thread/read","params":["threadId":session,"includeTurns":false]]) }
            }
        }
        guard let method = object["method"] as? String, let params = object["params"] as? [String:Any],
              let session = params["threadId"] as? String, !session.isEmpty, session.count <= 256 else { return }
        if method == "thread/status/changed", let status = params["status"] as? [String:Any] { update(session:session,status:status) }
        if ["turn/completed","thread/closed","thread/archived"].contains(method) { phases[session] = .idle; clear(session:session) }
        if method == "serverRequest/resolved", let wire = params["requestId"] {
            let matched = requests.filter { request in request.session == session && equalID(requestIDs[request.id],wire) }
            for request in matched { remove(request.id, confirmed:true) }
        }
        if let wire = object["id"], let request = Self.request(method:method,params:params) {
            guard requests.count < 24, !requests.contains(where: { $0.session == session && equalID(requestIDs[$0.id],wire) }) else { return }
            var available = request
            if available.kind == .permission, let decisions = params["availableDecisions"] as? [String], !decisions.contains("accept") { available.canReply = false }
            requests.append(available); requestIDs[request.id] = wire
            if params["isBlocking"] as? Bool != false { phases[session] = .waiting }
        }
        onChange?()
    }
    private func update(session:String,status:[String:Any]) {
        let type = status["type"] as? String
        let flags = status["activeFlags"] as? [String] ?? []
        phases[session] = type == "active" ? (flags.contains("waitingOnApproval") || flags.contains("waitingOnUserInput") ? .waiting : .running) : (type == "idle" ? .idle : .unknown)
        if phases[session] == .idle || phases[session] == .unknown { clear(session:session) }
        onChange?()
    }
    private func equalID(_ first:Any?,_ second:Any) -> Bool {
        guard let first else { return false }
        return (first as? String != nil && first as? String == second as? String) || (first as? Int != nil && first as? Int == second as? Int)
    }
    static func request(method:String,params:[String:Any]) -> AgentInputRequest? {
        guard let session = params["threadId"] as? String, let turn = params["turnId"] as? String else { return nil }
        if method == "item/tool/requestUserInput" {
            guard let raw = params["questions"] as? [[String:Any]], (1...3).contains(raw.count) else { return nil }
            let questions = raw.compactMap { item -> AgentQuestion? in
                guard let id = item["id"] as? String, id.count <= 128, let text = item["question"] as? String, text.count <= 2000 else { return nil }
                let options = (item["options"] as? [[String:Any]] ?? []).prefix(8).compactMap { option -> AgentQuestionOption? in
                    guard let label = option["label"] as? String, label.count <= 240 else { return nil }
                    return .init(label:label,detail:String((option["description"] as? String ?? "").prefix(500)))
                }
                return .init(id:id,text:text,options:options,allowsText:options.isEmpty || item["isOther"] as? Bool == true,secret:item["isSecret"] as? Bool == true)
            }
            guard questions.count == raw.count, Set(questions.map(\.id)).count == questions.count else { return nil }
            return .init(provider:.codex,session:session,turnID:turn,kind:.question,title:"Codex needs your input",questions:questions,canReply:true)
        }
        if ["item/commandExecution/requestApproval","item/fileChange/requestApproval"].contains(method) {
            return .init(provider:.codex,session:session,turnID:turn,kind:.permission,title:String((params["reason"] as? String ?? "Allow this action?").prefix(1000)),detail:(params["command"] as? String).map { String($0.prefix(4000)) },canReply:true)
        }
        return nil
    }
    func reply(_ value: AgentInputReply) async throws {
        try Task.checkCancellation()
        try value.validate()
        guard connected, let request = requests.first(where: { $0.id == value.requestID }), let wire = requestIDs[request.id],
              confirmations[request.id] == nil, request.canReply else { throw QuickTileError.failed("This request is no longer waiting for an answer.") }
        let result: [String:Any]
        if request.kind == .permission {
            guard let decision = value.decision, value.answers.isEmpty else { throw QuickTileError.invalid("Choose Allow once or Decline.") }
            result = ["decision":decision == .approveOnce ? "accept" : "decline"]
        } else {
            guard value.decision == nil, Set(value.answers.keys) == Set(request.questions.map(\.id)),
                  request.questions.allSatisfy({ question in question.allowsText || question.options.contains { $0.label == value.answers[question.id] } }) else {
                throw QuickTileError.invalid("Choose an answer for each question.")
            }
            result = ["answers":value.answers.mapValues { ["answers":[$0]] }]
        }
        if let index = requests.firstIndex(where: { $0.id == request.id }) { requests[index].canReply = false }
        try await withCheckedThrowingContinuation { continuation in
            confirmations[request.id] = continuation
            deadlines[request.id] = Task { [weak self] in
                try? await Task.sleep(for:.seconds(10)); guard !Task.isCancelled else { return }
                self?.confirmations.removeValue(forKey:request.id)?.resume(throwing:QuickTileError.failed("Codex hasn’t confirmed the answer. Check the request on your Mac."))
                self?.deadlines.removeValue(forKey:request.id)
            }
            do { try send(["id":wire,"result":result]) }
            catch { remove(request.id,confirmed:false) }
        }
    }
    private func remove(_ id:UUID,confirmed:Bool) {
        requests.removeAll { $0.id == id }; requestIDs.removeValue(forKey:id); deadlines.removeValue(forKey:id)?.cancel()
        if let continuation = confirmations.removeValue(forKey:id) {
            if confirmed { continuation.resume() } else { continuation.resume(throwing:QuickTileError.failed("The request ended before your answer was confirmed.")) }
        }
    }
    private func clear(session:String) { for id in requests.filter({ $0.session == session }).map(\.id) { remove(id,confirmed:false) } }
    func stop() {
        generation = UUID(); output?.readabilityHandler = nil; output = nil
        try? input?.close(); input = nil
        if let process, process.isRunning { process.terminate() }; process = nil
        for id in requests.map(\.id) { remove(id,confirmed:false) }
        phases = [:]; pending = Data(); readIDs = [:]; connected = false; onChange?()
    }
}
