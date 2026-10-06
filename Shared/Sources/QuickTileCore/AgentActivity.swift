import Foundation
import CryptoKit

public enum AgentProvider: String, Codable, CaseIterable, Sendable {
    case codex, claude
    public var title: String { self == .codex ? "Codex" : "Claude" }
    public var symbol: String { self == .codex ? "terminal" : "asterisk" }
    public var bundleIDs: [String] { self == .codex ? ["com.openai.codex"] : ["com.anthropic.claudefordesktop"] }
}
public enum AgentPhase: String, Codable, Sendable {
    case idle, running, waiting, unavailable, unknown
    public var label: String {
        switch self {
        case .idle: "Not running"
        case .running: "Running"
        case .waiting: "Waiting for input"
        case .unavailable: "Set up on Mac"
        case .unknown: "Status unavailable"
        }
    }
}
public enum AgentSource: String, Codable, CaseIterable, Sendable {
    case desktop, terminal, unknown
    public var label: String {
        switch self { case .desktop: "Desktop"; case .terminal: "Terminal"; case .unknown: "All sessions" }
    }
}
public enum AgentEvidenceSource: String, Codable, Sendable { case hooks, codexLog }
public enum AgentTrackingHealth: String, Codable, Sendable {
    case notConfigured, awaitingEvents, healthy, compatibility, stale
    public var label: String {
        switch self {
        case .notConfigured: "Set up on Mac"
        case .awaitingEvents: "Waiting for first event"
        case .healthy: "Receiving lifecycle events"
        case .compatibility: "Compatibility tracking"
        case .stale: "Tracking needs attention"
        }
    }
}
public struct AgentSnapshot: Codable, Equatable, Sendable {
    public var provider: AgentProvider
    public var phase: AgentPhase
    // Optional metadata keeps snapshots readable by previous companions/phones.
    public var health: AgentTrackingHealth?
    public var source: AgentSource?
    public var evidence: AgentEvidenceSource?
    public var updatedAt: Date?
    public var activeSessions: Int?
    public init(provider: AgentProvider, phase: AgentPhase, health: AgentTrackingHealth? = nil,
                source: AgentSource? = nil, evidence: AgentEvidenceSource? = nil,
                updatedAt: Date? = nil, activeSessions: Int? = nil) {
        self.provider = provider; self.phase = phase; self.health = health; self.source = source
        self.evidence = evidence; self.updatedAt = updatedAt; self.activeSessions = activeSessions
    }
}
public enum AgentLifecycle: String, Codable, Sendable {
    case sessionStarted, sessionResumed, turnStarted, activity, waiting, inputResolved
    case turnCompleted, interrupted, failed, sessionEnded
    case backgroundStarted, backgroundCompleted
    var endsTurn: Bool { [.turnCompleted, .interrupted, .failed, .sessionEnded].contains(self) }
}
public enum AgentInputKind: String, Codable, Sendable { case permission, question, elicitation, attention }
/// A bounded correlation record, never the tool arguments or user response.
public struct AgentPendingInput: Codable, Equatable, Sendable {
    public var requestID: String?
    public var actorID: String?
    public var kind: AgentInputKind?
    public var toolName: String?
    public var correlationHash: String?
    public var createdAt: Date?
    public var request: AgentInputRequest?
}
public struct AgentPendingTool: Codable, Equatable, Sendable {
    public var requestID: String
    public var actorID: String?
    public var toolName: String?
    public var correlationHash: String?
}
/// Only lifecycle metadata is retained; prompts, tool arguments and transcripts are discarded.
public struct AgentEvent: Codable, Equatable, Sendable {
    public var provider: AgentProvider
    public var session: String
    public var phase: AgentPhase
    public var updatedAt: Date
    public var lifecycle: AgentLifecycle?
    public var source: AgentSource?
    public var evidence: AgentEvidenceSource?
    public var turnID: String?
    public var waitingRequestID: String?
    public var toolName: String?
    public var correlationHash: String?
    public var inputKind: AgentInputKind?
    public var actorID: String?
    public var hookName: String?
    public var notificationType: String?
    // Reducer metadata survives the short-lived hook helper. All collections are bounded.
    public var pendingInputs: [AgentPendingInput]?
    public var pendingTools: [AgentPendingTool]?
    public var activeAgentIDs: [String]?
    public var backgroundTaskIDs: [String]?
    public var foregroundPhase: AgentPhase?
    public var foregroundClosed: Bool?
    public var pendingOverflow: Bool?
    public var toolOverflow: Bool?
    public var resolvedToolIDs: [String]?
    public var inputRequest: AgentInputRequest?
    public init(provider: AgentProvider, session: String, phase: AgentPhase, updatedAt: Date,
                lifecycle: AgentLifecycle? = nil, source: AgentSource? = nil,
                evidence: AgentEvidenceSource? = nil, turnID: String? = nil, waitingRequestID: String? = nil,
                toolName: String? = nil, correlationHash: String? = nil, inputKind: AgentInputKind? = nil,
                actorID: String? = nil, hookName: String? = nil, notificationType: String? = nil,
                backgroundTaskIDs: [String]? = nil, resolvedToolIDs: [String]? = nil) {
        self.provider = provider; self.session = session; self.phase = phase; self.updatedAt = updatedAt
        self.lifecycle = lifecycle; self.source = source; self.evidence = evidence
        self.turnID = turnID; self.waitingRequestID = waitingRequestID
        self.toolName = toolName; self.correlationHash = correlationHash; self.inputKind = inputKind
        self.actorID = actorID; self.hookName = hookName; self.notificationType = notificationType
        self.backgroundTaskIDs = backgroundTaskIDs
        self.resolvedToolIDs = resolvedToolIDs
    }
    public init?(provider: AgentProvider, input: Data, now: Date = Date()) {
        guard input.count <= 1_048_576,
              let json = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let session = Self.identifier(json["session_id"]),
              let event = json["hook_event_name"] as? String else { return nil }
        let tool = (json["tool_name"] as? String ?? "").lowercased()
        let actor = Self.compactIdentifier(json["agent_id"])
        let notification = json["notification_type"] as? String
        let lifecycle: AgentLifecycle
        var kind: AgentInputKind?
        switch event {
        case "SessionStart":
            lifecycle = ["compact", "resume"].contains(json["source"] as? String ?? "") ? .sessionResumed : .sessionStarted
        case "SessionEnd": lifecycle = .sessionEnded
        case "Stop":
            lifecycle = actor == nil ? .turnCompleted : .backgroundCompleted
        case "StopFailure": lifecycle = .failed
        case "Interrupt":
            guard provider == .codex else { return nil } // Claude does not expose an Interrupt hook.
            lifecycle = .interrupted
        case "SubagentStart": lifecycle = .backgroundStarted
        case "SubagentStop": lifecycle = .backgroundCompleted
        case "PermissionRequest": lifecycle = .waiting; kind = .permission
        case "PermissionDenied":
            guard provider == .claude else { return nil }
            lifecycle = .inputResolved; kind = .permission
        case "Elicitation": lifecycle = .waiting; kind = .elicitation
        case "ElicitationResult": lifecycle = .inputResolved; kind = .elicitation
        case "Notification":
            switch notification {
            case "permission_prompt": lifecycle = .waiting; kind = .permission
            case "elicitation_dialog", "elicitation_url_dialog": lifecycle = .waiting; kind = .elicitation
            case "elicitation_complete", "elicitation_response": lifecycle = .inputResolved; kind = .elicitation
            case "agent_needs_input", "quota_auto_resume_stale": lifecycle = .waiting; kind = .attention
            case "quota_auto_resume_fired": lifecycle = .inputResolved; kind = .attention
            case "quota_auto_resume_disabled": lifecycle = .turnCompleted
            case "idle_prompt", "agent_completed": lifecycle = .turnCompleted
            default: return nil
            }
        case "PreToolUse":
            lifecycle = Self.isInputTool(tool) ? .waiting : .activity
            if lifecycle == .waiting { kind = .question }
        case "UserPromptSubmit": lifecycle = .turnStarted
        case "PostToolUse", "PostToolUseFailure": lifecycle = .inputResolved
        case "PostToolBatch":
            guard provider == .claude else { return nil }
            lifecycle = .inputResolved
        default: return nil
        }
        let phase: AgentPhase
        switch lifecycle {
        case .waiting: phase = .waiting
        case .turnStarted, .activity, .inputResolved, .sessionResumed, .backgroundStarted: phase = .running
        default: phase = .idle
        }
        self.init(provider: provider, session: session, phase: phase, updatedAt: now, lifecycle: lifecycle,
                  source: Self.source(from: json["client"] ?? json["client_name"] ?? json["session_source"]),
                  evidence: .hooks, turnID: Self.identifier(provider == .claude ? (json["prompt_id"] ?? json["turn_id"]) : json["turn_id"]),
                  waitingRequestID: Self.compactIdentifier(json["tool_use_id"] ?? json["elicitation_id"]),
                  toolName: Self.compactIdentifier(json["tool_name"] ?? json["mcp_server_name"]),
                  correlationHash: Self.toolFingerprint(json["tool_input"], name: tool), inputKind: kind, actorID: actor,
                  hookName: event, notificationType: notification,
                  backgroundTaskIDs: provider == .claude ? (json["background_tasks"] as? [[String: Any]]).map { tasks in
                      Array(tasks.compactMap { Self.compactIdentifier($0["id"]) }.prefix(8))
                  } : nil,
                  resolvedToolIDs: (json["tool_calls"] as? [[String: Any]]).map { calls in
                      Array(calls.compactMap { Self.compactIdentifier($0["tool_use_id"]) }.prefix(8))
                  })
        if lifecycle == .waiting {
            inputRequest = AgentInputRequest.fromHook(json, provider: provider, session: session, turnID: turnID, now: now)
        }
    }
    public static func phase(for events: [Self], now: Date = Date()) -> AgentPhase {
        snapshot(provider: events.first?.provider ?? .codex, events: events, now: now).phase
    }
    public static func snapshot(provider: AgentProvider, events: [Self], configured: Bool = true,
                                source: AgentSource = .unknown, now: Date = Date()) -> AgentSnapshot {
        guard configured else { return .init(provider: provider, phase: .unavailable, health: .notConfigured) }
        let relevant = events.filter { $0.provider == provider && (source == .unknown || $0.source == source) }
        guard !relevant.isEmpty else { return .init(provider: provider, phase: .unknown, health: .awaitingEvents, source: source) }
        let sessions = Dictionary(grouping: relevant, by: \.session).values.compactMap { sessionEvents -> AgentSessionState? in
            reconciled(sessionEvents)
        }
        let fresh = sessions.filter { state in
            let age = now.timeIntervalSince(state.event.updatedAt)
            let maximum: TimeInterval = state.event.phase == .waiting ? 900 : 300
            return age >= -5 && (state.event.phase == .idle || age < maximum)
        }
        let active = fresh.filter { $0.event.phase == .running || $0.event.phase == .waiting }
        let selected = active.filter { $0.event.phase == .waiting }.max(by: { $0.event.updatedAt < $1.event.updatedAt })
            ?? active.max(by: { $0.event.updatedAt < $1.event.updatedAt })
            ?? fresh.max(by: { $0.event.updatedAt < $1.event.updatedAt })
        guard let event = selected?.event else {
            return .init(provider: provider, phase: .unknown, health: .stale, source: source,
                         updatedAt: relevant.map(\.updatedAt).max(), activeSessions: 0)
        }
        return .init(provider: provider, phase: event.phase,
                     health: now.timeIntervalSince(event.updatedAt) > 86_400 ? .stale : (event.evidence == .hooks && event.lifecycle != nil ? .healthy : .compatibility),
                     source: source == .unknown ? event.source : source, evidence: event.evidence,
                     updatedAt: event.updatedAt, activeSessions: active.count)
    }
    public static func pendingRequests(provider: AgentProvider, events: [Self], source: AgentSource = .unknown, now: Date = Date()) -> [AgentInputRequest] {
        let relevant = events.filter { $0.provider == provider && (source == .unknown || $0.source == source) }
        return Dictionary(grouping: relevant, by: \.session).values.flatMap { records -> [AgentInputRequest] in
            guard let event = reconciled(records)?.event, event.phase == .waiting, now.timeIntervalSince(event.updatedAt) < 900 else { return [] }
            return (event.pendingInputs ?? []).compactMap(\.request)
        }.sorted { $0.createdAt > $1.createdAt }
    }
    private static func reconciled(_ records: [Self]) -> AgentSessionState? {
        // Readers return complete reducer checkpoints, not every original hook. Replaying
        // only a checkpoint's last "activity" after an old closed turn discards the new turn.
        let ordered = records.sorted { $0.updatedAt < $1.updatedAt }
        let checkpoint = ordered.last { $0.evidence == .hooks && $0.foregroundPhase != nil }
            ?? ordered.last { $0.foregroundPhase != nil }
        var state = checkpoint.map(AgentSessionState.init)
        for record in ordered where checkpoint == nil || record.updatedAt > checkpoint!.updatedAt {
            if state == nil { state = .init(event: record) } else { state?.apply(record) }
        }
        return state
    }
    static func identifier(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty, value.utf8.count <= 256 else { return nil }
        return value
    }
    static func compactIdentifier(_ value: Any?) -> String? {
        guard let value = identifier(value) else { return nil }
        return value.utf8.count <= 128 ? value : "sha256:" + digest(Data(value.utf8))
    }
    static func toolFingerprint(_ value: Any?, name: String) -> String? {
        // Approval reasons and execution options differ between Pre/Permission/Post hooks.
        // Correlate shell calls by the actual command rather than the entire wrapper object.
        if ["bash", "exec_command", "shell", "shell_command"].contains(name.lowercased()),
           let input = value as? [String: Any], let command = (input["command"] ?? input["cmd"]) as? String {
            return fingerprint(["command": command])
        }
        return fingerprint(value)
    }
    static func fingerprint(_ value: Any?) -> String? {
        guard let value, let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]) else { return nil }
        return digest(bytes)
    }
    private static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    static func isInputTool(_ name: String) -> Bool {
        name.contains("askuserquestion") || name.contains("request_user_input")
    }
    public static func source(from value: Any?) -> AgentSource {
        guard let value = value as? String else { return .unknown }
        switch value.lowercased() {
        case "cli", "terminal", "exec": return .terminal
        case "desktop", "app-server", "codex_desktop", "claude_desktop", "codex desktop", "vscode": return .desktop
        case "codex_cli_rs", "claude-cli": return .terminal
        default: return .unknown
        }
    }
}
/// Reconciles ordered metadata without letting a late old-turn event revive a session.
public struct AgentSessionState: Sendable {
    public private(set) var event: AgentEvent
    public init(event: AgentEvent) {
        if event.foregroundPhase != nil {
            // Hook helpers exit after each event. Restore the complete reducer, not only its label.
            self.event = event
            self.event.pendingInputs = Array((event.pendingInputs ?? []).prefix(8))
            self.event.pendingTools = Array((event.pendingTools ?? []).prefix(8))
            self.event.activeAgentIDs = Array((event.activeAgentIDs ?? []).prefix(8))
            self.event.backgroundTaskIDs = Array((event.backgroundTaskIDs ?? []).prefix(8))
            // Older helpers retained id-less approval hashes for the full wrapper object,
            // making them impossible to reconcile after their tools completed. Do not
            // resurrect those ambiguous waits; require fresh lifecycle evidence instead.
            let legacy = (self.event.pendingInputs ?? []).filter { $0.kind == .permission && $0.requestID == nil && $0.createdAt == nil }
            if !legacy.isEmpty {
                self.event.pendingInputs?.removeAll { $0.kind == .permission && $0.requestID == nil && $0.createdAt == nil }
                self.event.pendingOverflow = false
                self.event.phase = .unknown
            }
        } else {
            var initial = event
            initial.phase = .idle; initial.lifecycle = nil; initial.turnID = nil
            initial.pendingInputs = []; initial.pendingTools = []; initial.activeAgentIDs = []
            initial.backgroundTaskIDs = []; initial.foregroundPhase = .idle; initial.foregroundClosed = false
            self.event = initial
            apply(event)
        }
    }
    public mutating func apply(_ incoming: AgentEvent) {
        guard incoming.provider == event.provider, incoming.session == event.session,
              incoming.updatedAt >= event.updatedAt else { return }
        let lifecycle = incoming.lifecycle ?? (incoming.phase == .waiting ? .waiting : (incoming.phase == .idle ? .turnCompleted : .activity))
        let child = incoming.actorID != nil
        if !child, let currentTurn = event.turnID, let nextTurn = incoming.turnID, currentTurn != nextTurn,
           lifecycle != .turnStarted, lifecycle != .sessionStarted, lifecycle != .sessionResumed, lifecycle != .sessionEnded { return }
        if !child, event.foregroundClosed == true,
           [.activity, .inputResolved, .waiting].contains(lifecycle) { return }
        // A compatibility record can corroborate a known request or turn, not manufacture a
        // resolution from another tool or an unscoped old transcript record.
        if event.evidence == .hooks, incoming.evidence == .codexLog,
           incoming.updatedAt.timeIntervalSince(event.updatedAt) < 300 {
            let matchingEnd = lifecycle.endsTurn && event.turnID != nil && incoming.turnID == event.turnID
            let newTurn = lifecycle == .turnStarted && incoming.turnID != nil && incoming.turnID != event.turnID
            let matchingInput = lifecycle == .inputResolved && incoming.waitingRequestID != nil &&
                (event.pendingInputs ?? []).contains { $0.requestID == incoming.waitingRequestID && $0.actorID == incoming.actorID }
            if !matchingEnd && !newTurn && !matchingInput { return }
        }
        var waits = event.pendingInputs ?? []
        var tools = event.pendingTools ?? []
        var agents = event.activeAgentIDs ?? []
        var background = event.backgroundTaskIDs ?? []
        var foreground = event.foregroundPhase ?? .idle
        var closed = event.foregroundClosed ?? false
        var overflow = event.pendingOverflow ?? false
        var toolOverflow = event.toolOverflow ?? false
        var turn = event.turnID
        let actor = AgentEvent.compactIdentifier(incoming.actorID)
        let request = AgentEvent.compactIdentifier(incoming.waitingRequestID)
        let name = AgentEvent.compactIdentifier(incoming.toolName)
        func sameActor(_ value: String?) -> Bool { value == actor }
        func correlate(_ wait: AgentPendingInput) -> String? {
            guard !toolOverflow else { return nil }
            let matches = tools.filter {
                $0.actorID == wait.actorID && (wait.toolName == nil || $0.toolName == wait.toolName) &&
                (wait.correlationHash == nil || $0.correlationHash == wait.correlationHash)
            }
            return matches.count == 1 ? matches[0].requestID : nil
        }
        func markAgent() {
            if let actor, !agents.contains(actor) { agents.append(actor); agents = Array(agents.prefix(8)) }
        }
        switch lifecycle {
        case .sessionStarted:
            waits = []; tools = []; agents = []; background = []; foreground = .idle; closed = false
            overflow = false; toolOverflow = false; turn = incoming.turnID
        case .sessionResumed:
            // Compaction or reopening is not evidence that a new prompt has started.
            break
        case .turnStarted:
            if child { markAgent() }
            else { foreground = .running; closed = false; turn = incoming.turnID; overflow = false; toolOverflow = false }
            waits.removeAll { sameActor($0.actorID) }; tools.removeAll { sameActor($0.actorID) }
        case .activity:
            if child { markAgent() } else { foreground = .running }
            if let request, !tools.contains(where: { $0.requestID == request && sameActor($0.actorID) }) {
                if tools.count < 8 { tools.append(.init(requestID: request, actorID: actor, toolName: name, correlationHash: incoming.correlationHash)) }
                else { toolOverflow = true }
            }
        case .waiting:
            if child { markAgent() } else { foreground = .running }
            if let request, incoming.hookName == "PreToolUse", !tools.contains(where: { $0.requestID == request && sameActor($0.actorID) }) {
                if tools.count < 8 { tools.append(.init(requestID: request, actorID: actor, toolName: name, correlationHash: incoming.correlationHash)) }
                else { toolOverflow = true }
            }
            var wait = AgentPendingInput(requestID: request, actorID: actor, kind: incoming.inputKind, toolName: name, correlationHash: incoming.correlationHash, createdAt: incoming.updatedAt, request: incoming.inputRequest)
            if wait.requestID == nil, wait.kind == .permission { wait.requestID = correlate(wait) }
            // Delayed notifications reinforce an existing wait; they must not create a second
            // unresolvable wait after the immediate PermissionRequest/Elicitation hook.
            let reinforcement = (incoming.hookName == "Notification" || (request == nil && incoming.inputKind == nil && name == nil)) &&
                waits.contains { sameActor($0.actorID) && ($0.kind == wait.kind || wait.kind == nil) }
            let duplicate = waits.contains {
                guard sameActor($0.actorID) else { return false }
                if let id = wait.requestID { return $0.requestID == id }
                return $0.requestID == nil && $0.kind == wait.kind && $0.toolName == wait.toolName && $0.correlationHash == wait.correlationHash
            }
            if !reinforcement && !duplicate {
                if waits.count < 8 { waits.append(wait) } else { overflow = true }
            }
        case .inputResolved:
            if child { markAgent() }
            let resolutions = incoming.resolvedToolIDs ?? request.map { [$0] } ?? []
            for id in resolutions {
                // An id-less PermissionRequest may be bound once its PreToolUse is the only
                // matching outstanding invocation. Ambiguity never clears a pending request.
                for index in waits.indices where waits[index].requestID == nil && waits[index].kind == .permission {
                    waits[index].requestID = correlate(waits[index])
                }
                waits.removeAll { sameActor($0.actorID) && $0.requestID == id &&
                    (incoming.inputKind == nil || $0.kind == nil || incoming.inputKind == $0.kind) }
                tools.removeAll { sameActor($0.actorID) && $0.requestID == id }
            }
            if let hash = incoming.correlationHash, let name,
               ["PostToolUse", "PostToolUseFailure", "PermissionDenied"].contains(incoming.hookName ?? "") {
                let matches = waits.indices.filter {
                    sameActor(waits[$0].actorID) && waits[$0].toolName == name && waits[$0].correlationHash == hash &&
                    (waits[$0].requestID == nil || waits[$0].requestID == request)
                }
                if matches.count == 1 { waits.remove(at: matches[0]) }
            }
            if request == nil, resolutions.isEmpty, let kind = incoming.inputKind {
                let matches = waits.indices.filter {
                    sameActor(waits[$0].actorID) && waits[$0].requestID == nil && waits[$0].kind == kind &&
                    (name == nil || waits[$0].toolName == name)
                }
                // Notification input has no request identity. Only resolve a solitary unknown
                // wait; duplicate/delayed notices cannot consume another identified request.
                if matches.count == 1 { waits.remove(at: matches[0]) }
            }
            for index in waits.indices where waits[index].requestID == nil && waits[index].kind == .permission {
                waits[index].requestID = correlate(waits[index])
            }
            if !child { foreground = .running }
        case .backgroundStarted:
            guard actor != nil else { return }; markAgent()
        case .backgroundCompleted:
            guard let actor else { return }
            agents.removeAll { $0 == actor }; waits.removeAll { $0.actorID == actor }; tools.removeAll { $0.actorID == actor }
        case .turnCompleted, .interrupted, .failed:
            if child {
                if let actor { agents.removeAll { $0 == actor } }
                waits.removeAll { sameActor($0.actorID) }; tools.removeAll { sameActor($0.actorID) }
            } else {
                foreground = .idle; closed = true
                waits.removeAll { $0.actorID == nil }; tools.removeAll { $0.actorID == nil }
                overflow = false; toolOverflow = false
            }
        case .sessionEnded:
            waits = []; tools = []; agents = []; background = []; foreground = .idle; closed = true
            overflow = false; toolOverflow = false
        }
        if let snapshot = incoming.backgroundTaskIDs, lifecycle != .sessionEnded {
            background = Array(snapshot.prefix(8))
            // Stop/SubagentStop describe all in-flight parent tasks. An empty snapshot is
            // stronger evidence than an old SubagentStart record.
            if snapshot.isEmpty { agents = []; waits.removeAll { $0.actorID != nil }; tools.removeAll { $0.actorID != nil } }
        }
        var next = incoming
        next.inputRequest = nil
        next.turnID = turn ?? incoming.turnID
        next.foregroundPhase = foreground; next.foregroundClosed = closed
        next.pendingInputs = waits; next.pendingTools = tools; next.activeAgentIDs = agents; next.backgroundTaskIDs = background
        next.pendingOverflow = overflow; next.toolOverflow = toolOverflow
        next.phase = !waits.isEmpty || overflow ? .waiting : (foreground == .running || !agents.isEmpty || !background.isEmpty ? .running : .idle)
        next.waitingRequestID = waits.first?.requestID
        if next.source == nil || next.source == .unknown { next.source = event.source }
        // Preserve hook authority after a matching compatibility completion.
        if event.evidence == .hooks && incoming.evidence == .codexLog { next.evidence = .hooks }
        event = next
    }
}

/// Pure configuration transformation. Only QuickTile-owned handlers are replaced or removed.
public enum AgentHookConfiguration {
    public static func requiredEvents(for provider: AgentProvider) -> [String] {
        provider == .codex
            ? ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "SubagentStart", "SubagentStop", "Stop", "Interrupt", "SessionEnd"]
            : ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PermissionDenied", "PostToolUse", "PostToolUseFailure", "PostToolBatch", "Notification", "Elicitation", "ElicitationResult", "SubagentStart", "SubagentStop", "Stop", "StopFailure", "SessionEnd"]
    }
    public static func update(_ data: Data, provider: AgentProvider, command: String, removing: Bool = false) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["hooks"] == nil || root["hooks"] is [String: Any] else { throw invalidConfiguration() }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let desired = requiredEvents(for: provider)
        // Inspect all event names so retired handlers are removed as well.
        for event in Set(hooks.keys).union(desired) {
            guard hooks[event] == nil || hooks[event] is [[String: Any]] else { throw invalidConfiguration() }
            let matchers = hooks[event] as? [[String: Any]] ?? []
            var preserved: [[String: Any]] = []
            for var matcher in matchers {
                guard let handlers = matcher["hooks"] as? [[String: Any]] else { throw invalidConfiguration() }
                let remaining = handlers.filter { handler in
                    guard let value = handler["command"] as? String else { return true }
                    let helper = executable(in: value, suffix: " " + provider.rawValue).map { URL(fileURLWithPath: $0).lastPathComponent == "QuickTileAgentEvent" } == true
                    let legacy = executable(in: value, suffix: " --agent-event " + provider.rawValue).map { URL(fileURLWithPath: $0).lastPathComponent == "QuickTileMac" } == true
                    return !(helper || legacy || value == command)
                }
                if !remaining.isEmpty { matcher["hooks"] = remaining; preserved.append(matcher) }
            }
            if !removing && desired.contains(event) {
                // Events without matching omit `matcher`, matching vendor configuration examples.
                var entry: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": 3]]]
                if ["SessionStart", "PreToolUse", "PermissionRequest", "PermissionDenied", "PostToolUse", "PostToolUseFailure", "Notification", "SubagentStart", "SubagentStop", "SessionEnd"].contains(event) { entry["matcher"] = "*" }
                preserved.append(entry)
            }
            if preserved.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = preserved }
        }
        root["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }
    private static func invalidConfiguration() -> NSError {
        NSError(domain: "QuickTileAgentStatus", code: 2, userInfo: [NSLocalizedDescriptionKey: "The agent configuration is not valid JSON hook configuration. It was left unchanged."])
    }
    private static func executable(in command: String, suffix: String) -> String? {
        guard command.hasSuffix(suffix) else { return nil }
        let quoted = String(command.dropLast(suffix.count))
        guard quoted.hasPrefix("'"), quoted.hasSuffix("'"), quoted.count > 2 else { return nil }
        let path = String(quoted.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'")
        let encoded = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        // Match a complete invocation; text mentioning QuickTile is not an owned hook.
        guard quoted == encoded, path.hasPrefix("/") else { return nil }
        return path
    }
}
extension AgentEvent {
    /// Item `status: completed` never means that the whole turn finished.
    public static func codexEvents(in data: Data, session: String, source: AgentSource = .unknown) -> [AgentEvent] {
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        return data.split(separator: 10).compactMap { line in
            guard line.count <= 2_097_152,
                  let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let timestamp = json["timestamp"] as? String,
                  let date = fractional.date(from: timestamp) ?? plain.date(from: timestamp),
                  let payload = json["payload"] as? [String: Any],
                  let type = payload["type"] as? String else { return nil }
            var lifecycle: AgentLifecycle?
            if json["type"] as? String == "event_msg" {
                switch type {
                case "task_started", "turn_started", "user_message": lifecycle = .turnStarted
                case "task_complete", "turn_completed": lifecycle = .turnCompleted
                case "turn_aborted", "task_interrupted": lifecycle = .interrupted
                case "turn_failed": lifecycle = .failed
                default: break
                }
            } else if json["type"] as? String == "response_item" {
                switch type {
                case "reasoning": lifecycle = .activity
                case "function_call", "custom_tool_call":
                    lifecycle = isInputTool((payload["name"] as? String ?? "").lowercased()) ? .waiting : .activity
                case "function_call_output", "custom_tool_call_output": lifecycle = .inputResolved
                case "message":
                    if payload["role"] as? String == "assistant" {
                        let final = payload["phase"] as? String == "final" || payload["channel"] as? String == "final"
                        lifecycle = final ? .turnCompleted : .activity
                    }
                default: break
                }
            }
            guard let lifecycle else { return nil }
            let phase: AgentPhase = lifecycle == .waiting ? .waiting : (lifecycle.endsTurn ? .idle : .running)
            var event = AgentEvent(provider: .codex, session: session, phase: phase, updatedAt: date, lifecycle: lifecycle,
                         source: source, evidence: .codexLog, turnID: identifier(payload["turn_id"] ?? json["turn_id"]),
                         waitingRequestID: identifier(payload["call_id"]))
            if lifecycle == .waiting, let arguments = payload["arguments"] as? String,
               let input = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any] {
                event.inputRequest = AgentInputRequest.fromHook(["tool_input":input, "tool_use_id":payload["call_id"] as Any], provider: .codex, session: session, turnID: event.turnID, now: date)
            }
            return event
        }
    }
    public static func codexActivity(in data: Data, session: String) -> AgentEvent? {
        var state: AgentSessionState?
        for event in codexEvents(in: data, session: session) {
            if state == nil { state = .init(event: event) } else { state?.apply(event) }
        }
        return state?.event
    }
}

public struct AgentQuestionOption: Codable, Equatable, Sendable {
    public var label: String
    public var detail: String
    public init(label: String, detail: String = "") { self.label = label; self.detail = detail }
}
public struct AgentQuestion: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var options: [AgentQuestionOption]
    public var allowsText: Bool
    public var secret: Bool
    public init(id: String, text: String, options: [AgentQuestionOption] = [], allowsText: Bool = true, secret: Bool = false) {
        self.id = id; self.text = text; self.options = options; self.allowsText = allowsText; self.secret = secret
    }
}
public enum AgentReplyDecision: String, Codable, Sendable { case approveOnce, deny }
public struct AgentInputRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var provider: AgentProvider
    public var session: String
    public var turnID: String?
    public var kind: AgentInputKind
    public var createdAt: Date
    public var title: String
    public var detail: String?
    public var questions: [AgentQuestion]
    public var canReply: Bool
    public init(id: UUID = UUID(), provider: AgentProvider, session: String, turnID: String? = nil, kind: AgentInputKind,
                createdAt: Date = Date(), title: String, detail: String? = nil, questions: [AgentQuestion] = [], canReply: Bool = false) {
        self.id = id; self.provider = provider; self.session = session; self.turnID = turnID; self.kind = kind
        self.createdAt = createdAt; self.title = title; self.detail = detail; self.questions = questions; self.canReply = canReply
    }
    static func fromHook(_ json: [String: Any], provider: AgentProvider, session: String, turnID: String?, now: Date) -> Self? {
        guard let input = json["tool_input"] as? [String: Any] else { return nil }
        let permission = json["hook_event_name"] as? String == "PermissionRequest"
        if permission {
            let description = (input["description"] ?? input["justification"]) as? String ?? "Allow this action?"
            let command = (input["command"] ?? input["cmd"]) as? String
            return .init(provider: provider, session: session, turnID: turnID, kind: .permission, createdAt: now,
                         title: String(description.prefix(1000)), detail: command.map { String($0.prefix(4000)) })
        }
        guard let raw = input["questions"] as? [[String: Any]], !raw.isEmpty, raw.count <= 3 else { return nil }
        let questions = raw.enumerated().compactMap { index, value -> AgentQuestion? in
            // Secret requests never get copied from compatibility transcripts to another device.
            guard value["isSecret"] as? Bool != true, let text = (value["question"] ?? value["title"]) as? String, !text.isEmpty else { return nil }
            let options = (value["options"] as? [[String: Any]] ?? []).prefix(8).compactMap { option -> AgentQuestionOption? in
                guard let label = option["label"] as? String else { return nil }
                return .init(label: String(label.prefix(240)), detail: String((option["description"] as? String ?? "").prefix(500)))
            }
            return .init(id: String((value["id"] as? String ?? "question-\(index)").prefix(128)), text: String(text.prefix(2000)), options: options,
                         allowsText: options.isEmpty || value["isOther"] as? Bool == true || input["questions"] != nil)
        }
        guard !questions.isEmpty else { return nil }
        return .init(provider: provider, session: session, turnID: turnID, kind: .question, createdAt: now,
                     title: "Codex needs your input", questions: questions)
    }
}
public struct AgentInputReply: Codable, Sendable {
    public var sessionID: UUID
    public var createdAt: Date
    public var requestID: UUID
    public var answers: [String: String]
    public var decision: AgentReplyDecision?
    public init(sessionID: UUID, createdAt: Date, requestID: UUID, answers: [String: String] = [:], decision: AgentReplyDecision? = nil) {
        self.sessionID = sessionID; self.createdAt = createdAt; self.requestID = requestID; self.answers = answers; self.decision = decision
    }
    public func validate() throws {
        guard answers.count <= 3, answers.allSatisfy({ !$0.key.isEmpty && $0.key.count <= 128 && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.value.count <= 2000 && !$0.value.contains("\0") }),
              decision == nil || answers.isEmpty else { throw NSError(domain:"QuickTileAgentReply",code:1,userInfo:[NSLocalizedDescriptionKey:"Enter an answer for each question."]) }
    }
}
