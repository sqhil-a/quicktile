import SwiftUI
import Combine
import UIKit
import AudioToolbox
import Network
import CryptoKit
import QuickTileCore
import UserNotifications
import os

@MainActor final class MacControlStore: ObservableObject {
    @Published private(set) var state: ControlState?
    @Published private(set) var available = false
    @Published private(set) var error: String?
    var send: ((UUID, ControlKind?, Double?) -> Void)?
    private var queued: [ControlKind: Double] = [:]
    private var flight: (id: UUID, kind: ControlKind?, value: Double?, sent: Date)?
    private var task: Task<Void, Never>?
    private var open = false
    private var lastPoll = Date.distantPast
    private var restoreVolume: Double?
    private var volumeMemoryKey: String?
    private var macID: UUID?
    private var outputDeviceID: UInt32?
    func selectMac(_ id: UUID) {
        macID = id; outputDeviceID = nil; volumeMemoryKey = nil; restoreVolume = nil
    }
    private func rememberVolume(_ value: Double) {
        guard value.isFinite, value > 0, value <= 1 else { return }
        restoreVolume = value
        if let volumeMemoryKey { UserDefaults.standard.set(value, forKey: volumeMemoryKey) }
    }
    @discardableResult func toggleVolume() -> Double? {
        guard available, let current = value(.volume) else { return nil }
        let target: Double
        if current > 0 {
            rememberVolume(current)
            target = 0
        } else {
            guard let restoreVolume, restoreVolume > 0 else { return nil }
            target = restoreVolume
        }
        adjust(.volume, value: target)
        return target
    }
    func setAvailable(_ available: Bool) {
        guard self.available != available else { return }
        self.available = available
        if !available { task?.cancel(); task = nil; queued = [:]; flight = nil; state = nil }
        else if open { start() }
    }
    func start() {
        open = true
        guard available, task == nil else { return }
        error = nil; lastPoll = .distantPast
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.pump()
                if !self.open && self.queued.isEmpty && self.flight == nil { self.task = nil; return }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }
    func close() { open = false }
    func adjust(_ kind: ControlKind, value: Double) {
        guard available, value.isFinite else { return }
        if kind == .volume {
            if value > 0 { rememberVolume(min(1, value)) }
            else if let current = self.value(.volume) { rememberVolume(current) }
        }
        queued[kind] = min(1, max(0, value))
        if error != nil { error = nil }
    }
    func value(_ kind: ControlKind) -> Double? {
        if let value = queued[kind] { return value }
        if let flight, flight.kind == kind { return flight.value }
        return kind == .volume ? (state?.muted == true ? 0 : state?.volume) : state?.brightness
    }
    private func pump() {
        if let flight, Date().timeIntervalSince(flight.sent) > 5 {
            self.flight = nil; queued = [:]; error = "Mac didn’t respond. Try again."; state = nil
        }
        guard available, flight == nil else { return }
        let kind = ControlKind.allCases.first { queued[$0] != nil }
        guard kind != nil || (open && Date().timeIntervalSince(lastPoll) >= 1) else { return }
        let value = kind.flatMap { queued.removeValue(forKey: $0) }
        let id = UUID(); flight = (id, kind, value, Date()); lastPoll = Date()
        send?(id, kind, value)
    }
    func receive(id: UUID, value: ControlState) {
        guard flight?.id == id else { return }
        if outputDeviceID != value.outputDeviceID {
            outputDeviceID = value.outputDeviceID
            volumeMemoryKey = macID.flatMap { mac in value.outputDeviceID.map { "dialVolumeBeforeMute.\(mac.uuidString).\($0)" } }
            restoreVolume = volumeMemoryKey.flatMap { UserDefaults.standard.object(forKey: $0) as? Double }
            queued[.volume] = nil
        }
        if let restore = value.restoreLevel { rememberVolume(restore) }
        else if queued[.volume] == nil, value.muted != true, let volume = value.volume { rememberVolume(volume) }
        flight = nil; state = value
    }
    func receiveError(id: UUID, result: ActionResult) -> Bool {
        guard flight?.id == id, result.status == .failed else { return false }
        flight = nil; queued = [:]; state = nil; error = result.message
        return true
    }
}

@MainActor final class PhoneModel: ObservableObject {
    @Published private(set) var state: ConnectionState = .offline
    @Published private(set) var nearby: [NearbyMac] = []
    @Published private(set) var credentials: [Credential] = []
    @Published private(set) var selected: Credential?
    @Published var layout: DeckLayout? { didSet { persist() } }
    @Published private(set) var apps: [AppEntry] = []
    @Published private(set) var shortcuts: [ShortcutEntry] = []
    @Published private(set) var capabilities = Capabilities()
    let images: PhoneImages
    let controls = MacControlStore()
    let timers = TileTimerStore()
    let assistant = VoiceAssistantStore()
    @Published var assistantConsentTile: Tile?
    @Published var agentRequestProvider: AgentProvider?
    @Published private(set) var agentRequests: [AgentInputRequest] = []
    @Published private(set) var agentRequestLoading = false
    @Published private(set) var agentReplyBusy = false
    @Published private(set) var agentRequestError: String?
    private var agentRequestSource: AgentSource = .unknown
    private var agentFetchID: UUID?
    private var agentReplyID: UUID?
    private var agentRequestTimeout: Task<Void, Never>?
    private var assistantCompletions: [UUID: (String, Bool) -> Void] = [:]
    private(set) var appByID: [String: AppEntry] = [:]
    @Published private(set) var catalogRevision = UUID()
    @Published private(set) var catalogNote: String?
    @Published private(set) var busyTiles = Set<UUID>()
    @Published private(set) var sequenceProgress: [UUID: SequenceProgress] = [:]
    @Published private(set) var frontmostBundleID: String?
    @Published private(set) var undoAvailable = false
    @Published private(set) var previewMode = false
    @Published var choosingFirstBoard = false
    private var newlyPaired = false
    @Published private(set) var pairingStage: PairingStage?
    private var removalHistory: [DeckLayout] = []
    func agentSnapshot(_ provider: AgentProvider, source: AgentSource? = nil) -> AgentSnapshot? {
        #if DEBUG
        if uiTest && ProcessInfo.processInfo.arguments.contains("--ui-testing-agent-requests") { return capabilities.agents?.first { $0.provider == provider } }
        #endif
        guard state == .connected && !macPaused else { return AgentSnapshot(provider: provider, phase: .unknown) }
        if let source, source != .unknown { return capabilities.agentSources?.first { $0.provider == provider && $0.source == source } ?? .init(provider: provider, phase: .unknown, health: .awaitingEvents, source: source) }
        return capabilities.agents?.first { $0.provider == provider }
    }
    @Published var error: String? { didSet { if error != nil && error != oldValue { feedback(.error) } } }
    @Published var activity: String?
    @Published var scanning = false { didSet { if scanning { pairingStage = .scanning } else if pairingStage == .scanning { pairingStage = .cancelled } } }
    @Published private(set) var macPaused = false
    private let discovery = Discovery()
    private let vault = KeychainStore(service: "sahil.QuickTile.credentials")
    private let storage: LayoutStore
    private let writer: LayoutWriter
    private var saveTask: Task<Void, Never>?
    private var layoutRevision = 0
    private let cache: URL
    private var channel: WireChannel?
    private var sessionID: UUID?
    private var clockOffset: TimeInterval = 0
    private var invite: PairingInvite?
    private var foreground = false
    private var reconnect: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var authTimeout: Task<Void, Never>?
    private var backoff: Double = 1
    private var pending: [UUID: (tile: UUID, timer: Task<Void, Never>)] = [:]
    private var testCompletions: [UUID: (title: String, callback: @MainActor (String, Bool) -> Void)] = [:]
    private let signposter = OSSignposter(subsystem: "sahil.QuickTile", category: "Actions")
    private var commandIntervals: [UUID: OSSignpostIntervalState] = [:]
    private var iconQueue = IconRequestQueue()
    private var iconPump: Task<Void, Never>?
    private var incomingApps: [AppEntry] = []
    private var incomingShortcuts: [ShortcutEntry] = []
    private var nextCatalogIndex = 0
    private var generation: UUID?
    private var loading = false
    private var allowSaving = true
    private var activityTask: Task<Void, Never>?
    private var activityID = UUID()
    private var uiTest = false
    enum Feedback { case soft, rigid, selection, success, error, dialTick, dialLimit, editMode, timerComplete }
    private let softFeedback = UIImpactFeedbackGenerator(style: .soft)
    private let rigidFeedback = UIImpactFeedbackGenerator(style: .rigid)
    private let limitFeedback = UIImpactFeedbackGenerator(style: .heavy)
    private var lastLimitFeedback = Date.distantPast
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let notificationFeedback = UINotificationFeedbackGenerator()
    private var lastFeedback = Date.distantPast
    private var timerHapticTask: Task<Void, Never>?
    func playTimerHaptic(_ pattern: TimerHapticPattern, timerID: UUID? = nil) {
        timerHapticTask?.cancel()
        guard pattern != .off, layout?.settings.haptics != false, UIApplication.shared.applicationState == .active else { return }
        timerHapticTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for index in 0..<(pattern == .doubleClick ? 2 : 1) {
                if index > 0 { do { try await Task.sleep(for:.milliseconds(140)) } catch { return } }
                guard !Task.isCancelled, self.layout?.settings.haptics != false, UIApplication.shared.applicationState == .active,
                      timerID == nil || self.timers.values[timerID!]?.finished == true else { return }
                switch pattern {
                case .click, .doubleClick: self.rigidFeedback.impactOccurred(intensity:0.9)
                case .soft: self.softFeedback.impactOccurred(intensity:0.8)
                case .pulse: self.limitFeedback.impactOccurred(intensity:0.85)
                case .alert: self.notificationFeedback.notificationOccurred(.warning)
                case .vibration: AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                case .off: break
                }
            }
        }
    }
    func prepareEditFeedback() {
        guard layout?.settings.haptics != false else { return }
        limitFeedback.prepare()
    }
    func feedback(_ kind: Feedback) {
        guard layout?.settings.haptics != false else { return }
        let now = Date()
        if kind == .dialLimit {
            guard now.timeIntervalSince(lastLimitFeedback) > 0.15 else { return }
            lastLimitFeedback = now; lastFeedback = now
            limitFeedback.impactOccurred(intensity: 1)
            return
        }
        guard now.timeIntervalSince(lastFeedback) > 0.09 else { return }
        lastFeedback = now
        switch kind {
        case .timerComplete: rigidFeedback.impactOccurred(intensity: 0.9)
        case .editMode: limitFeedback.impactOccurred(intensity: 0.9)
        case .soft: softFeedback.impactOccurred(intensity: 0.55)
        case .rigid: rigidFeedback.impactOccurred(intensity: 0.45)
        case .selection: selectionFeedback.selectionChanged()
        case .success: notificationFeedback.notificationOccurred(.success)
        case .error: notificationFeedback.notificationOccurred(.error)
        case .dialTick: rigidFeedback.impactOccurred(intensity: 0.35)
        case .dialLimit: break
        }
    }
    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QuickTile", isDirectory: true)
        storage = LayoutStore(directory: support.appendingPathComponent("Layouts"))
        writer = LayoutWriter(store: storage)
        cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MacIcons")
        images = PhoneImages(directory: cache)
        timers.onError = { [weak self] message in self?.error = message }
        controls.send = { [weak self] id, kind, value in
            guard let self, self.state == .connected, let channel = self.channel, let sessionID = self.sessionID,
                  self.capabilities.controlsVersion == 1 else { return }
            if let kind, let value {
                channel.send(Envelope(id: id, payload: .adjustControl(ControlAdjustment(sessionID: sessionID, createdAt: Date().addingTimeInterval(self.clockOffset), kind: kind, value: value, displayID: self.controls.state?.displayID))))
            } else { channel.send(Envelope(id: id, payload: .controlsRequest)) }
        }
        images.requestApp = { [weak self] version in
            guard version.count == 64, version.allSatisfy({ $0.isHexDigit }), let self else { return }
            self.iconQueue.enqueue(version); self.pumpIcons()
        }
        #if DEBUG
        uiTest = ProcessInfo.processInfo.arguments.contains("--ui-testing-deck") || ProcessInfo.processInfo.arguments.contains("--ui-testing-onboarding") || ProcessInfo.processInfo.arguments.contains("--ui-testing-full-deck") || ProcessInfo.processInfo.arguments.contains("--ui-testing-large-catalog")
        #endif
        if !uiTest {
            do { credentials = try vault.read([Credential].self, account: "macs") ?? [] }
            catch { self.error = error.localizedDescription }
        }
        discovery.onChange = { [weak self] values in
            guard let self else { return }; self.nearby = values
            if self.channel == nil { self.connectIfPossible() }
        }
        discovery.onState = { [weak self] state, detail in
            guard let self, self.channel == nil else { return }; self.state = state
            if let detail { self.error = detail }
        }
        if let id = UserDefaults.standard.string(forKey: "selectedMac"), let found = credentials.first(where: { $0.macID.uuidString == id }) { select(found) }
        else if let first = credentials.first { select(first) }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-deck") || ProcessInfo.processInfo.arguments.contains("--ui-testing-full-deck") || ProcessInfo.processInfo.arguments.contains("--ui-testing-large-catalog") {
            uiTest = true; allowSaving = false; credentials = []; selected = nil; error = nil
            layout = DeckLayout(macID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-full-deck") {
                let names = ["Safari", "Mail", "Calendar", "Notes", "Music", "Messages", "Photos", "Settings", "TextEdit"]
                let symbols = ["safari", "envelope", "calendar", "note.text", "music.note", "message", "photo", "gearshape", "doc.text"]
                layout?.pages[0].tiles = names.enumerated().map { index, name in
                    Tile(name: name, symbol: symbols[index], action: .launchApp(bundleID: "test.\(name)"))
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-agent-requests") {
                layout?.pages[0].tiles[0] = Tile(name:"Codex",symbol:"terminal",action:.agent(.codex))
                capabilities.agents = [.init(provider:.codex,phase:.waiting)]
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-assistant") {
                layout?.pages[0].tiles[0] = Tile(name: "Assistant", symbol: "waveform", action: .assistant)
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-large-catalog") {
                let data = UIImage(systemName: "app.fill")!.pngData()!
                let hash = ImageDisk.digest(data)
                _ = images.resource(.app(hash))
                installCatalog(apps: (0..<1500).map {
                    AppEntry(id: "test.app.\($0)", name: String(format: "Application %04d", $0), iconVersion: hash)
                }, shortcuts: [])
                Task { _ = await images.receive(IconAsset(version: hash, png: data)) }
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-dials") {
                var snapshot = ControlState(volume: 0.3, brightness: 0.5, displayID: 1, displayName: "Built-in display")
                controls.send = { [weak self] id, kind, value in
                    if let kind, let value {
                        if kind == .volume { snapshot.volume = value } else { snapshot.brightness = value }
                    }
                    self?.controls.receive(id: id, value: snapshot)
                }
                controls.setAvailable(true)
            }
        }
        #endif
    }
    func setForeground(_ active: Bool) {
        foreground = active
        #if DEBUG
        if uiTest && ProcessInfo.processInfo.arguments.contains("--ui-testing-dials") {
            controls.setAvailable(active)
        }
        #endif
        if active { if !uiTest { discovery.start(); connectIfPossible() } }
        else { flushLayout(); reconnect?.cancel(); reconnect = nil; discovery.stop(); disconnect(); state = .offline }
        timers.setNotificationsEnabled(layout?.settings.timerNotifications == true)
        updateIdleTimer()
        updateDialPolling()
    }
    private func updateDialPolling() {
        let hasDials = layout?.pages.contains { $0.tiles.contains { if case .dial = $0.action { return true }; return false } } ?? false
        if foreground && hasDials { controls.start() } else { controls.close() }
    }
    func select(_ credential: Credential) {
        previewMode = false
        pairingStage = nil
        flushLayout()
        disconnect(); invite = nil; selected = credential; generation = nil
        controls.selectMac(credential.macID)
        timers.selectMac(credential.macID)
        clearRemovalHistory()
        apps = []; shortcuts = []; appByID = [:]; iconQueue = IconRequestQueue(); images.resetAppRequests()
        incomingApps = []; incomingShortcuts = []; nextCatalogIndex = 0
        UserDefaults.standard.set(credential.macID.uuidString, forKey: "selectedMac")
        loading = true; allowSaving = true
        do { layout = try storage.load(macID: credential.macID) }
        catch { allowSaving = false; layout = nil; self.error = error.localizedDescription }
        loading = false
        if let data = try? Data(contentsOf: catalogURL(credential.macID)), let snapshot = try? JSONDecoder().decode(CatalogSnapshot.self, from: data) {
            installCatalog(apps: snapshot.apps, shortcuts: snapshot.shortcuts)
        }
        connectIfPossible()
    }
    func pair(_ text: String) {
        do {
            let value = try PairingInvite.decode(text.trimmingCharacters(in: .whitespacesAndNewlines))
            if previewMode { leavePreview() }
            disconnect(); invite = value; scanning = false; error = nil; state = .connecting; pairingStage = .connecting
            discovery.start(); connectIfPossible()
        } catch { scanning = false; pairingStage = .failed; self.error = error.localizedDescription }
    }
    func cancelPairing() { invite = nil; pairingStage = .cancelled; disconnect(); connectIfPossible() }
    func retry() { backoff = 1; disconnect(); discovery.stop(); discovery.start(); connectIfPossible() }
    func forget(_ credential: Credential) {
        do {
            let remaining = credentials.filter { $0.macID != credential.macID }
            try vault.write(remaining, account: "macs"); credentials = remaining
            if selected?.macID == credential.macID { disconnect(); selected = nil; loading = true; layout = nil; loading = false; state = .searching }
        } catch { self.error = error.localizedDescription }
    }
    func refreshCatalog() { if state == .connected { channel?.send(Envelope(payload: .catalogRequest)) } }
    func approveAssistant() {
        guard let tile = assistantConsentTile else { return }
        UserDefaults.standard.set(true, forKey: "groqTranscriptConsent.v1")
        assistantConsentTile = nil; activateAssistant(tile)
    }
    func activateAssistant(_ tile: Tile) {
        #if DEBUG
        if uiTest && ProcessInfo.processInfo.arguments.contains("--ui-testing-assistant") { assistant.toggleFixture(tile.id); return }
        #endif
        guard !previewMode else { setActivity("Preview only"); return }
        if assistant.tileID == tile.id { assistant.toggle(tile.id); return }
        let availability = self.availability(for: .assistant)
        guard availability.isReady else { error = availability.message; return }
        guard UserDefaults.standard.bool(forKey: "groqTranscriptConsent.v1") else { assistantConsentTile = tile; return }
        assistant.submit = { [weak self] id, text, completion in self?.sendAssistant(tileID: id, text: text, completion: completion) }
        assistant.cancelRequest = { [weak self] id in self?.cancelAssistant(tileID: id) }
        assistant.feedback = { [weak self] in self?.feedback($0) }
        assistant.toggle(tile.id)
    }
    func assistantFeedback(_ text: String?) {
        guard let text else { return }
        setActivity(text)
    }
    private func sendAssistant(tileID: UUID, text: String, completion: @escaping (String, Bool) -> Void) {
        guard state == .connected, let sessionID, let channel else { completion("Connect to your Mac.", false); return }
        let id = UUID(); assistantCompletions[id] = completion; busyTiles.insert(tileID)
        let timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(345))
            guard !Task.isCancelled, let self else { return }
            self.channel?.send(Envelope(payload: .cancelCommand(id)))
            let callback = self.assistantCompletions.removeValue(forKey: id); self.finish(id)
            callback?("No completion received. Check your Mac before retrying.", false)
        }
        pending[id] = (tileID, timer)
        channel.send(Envelope(id: id, payload: .assistantRequest(.init(sessionID: sessionID, createdAt: Date().addingTimeInterval(clockOffset), text: text))))
    }
    private func cancelAssistant(tileID: UUID) {
        guard let request = pending.first(where: { $0.value.tile == tileID && assistantCompletions[$0.key] != nil }) else { return }
        channel?.send(Envelope(payload: .cancelCommand(request.key)))
        assistantCompletions.removeValue(forKey: request.key); finish(request.key)
    }
    func execute(_ tile: Tile) { execute(tile, testCompletion: nil) }
    private func execute(_ tile: Tile, testCompletion: (@MainActor (String, Bool) -> Void)?) {
        func reject(_ message: String) {
            if let testCompletion { testCompletion(message, false); feedback(.error) }
            else { error = message }
        }
        if case .agent(let provider) = tile.action, testCompletion == nil,
           agentSnapshot(provider,source:tile.agentSource)?.phase == .waiting {
            openAgentRequests(provider,source:tile.agentSource ?? .unknown); return
        }
        if case .assistant = tile.action { activateAssistant(tile); return }
        if case .timer(let seconds) = tile.action { timers.toggle(tile.id, seconds: seconds); testCompletion?("Updated timer", true); feedback(.soft); return }
        if previewMode {
            if let testCompletion { testCompletion("Preview only", true) } else { setActivity("Preview only") }
            feedback(.soft); return
        }
        guard state.permitsActions, let sessionID, let channel, !busyTiles.contains(tile.id) else {
            reject(!state.permitsActions ? "Connect to your Mac before using this tile." : "Wait for this tile to finish."); return
        }
        if case .sequence = tile.action, capabilities.sequenceVersion != 1 {
            reject("Update the Mac companion to use sequences."); return
        }
        let availability = ActionRegistry.availability(action: tile.action, capabilities: capabilities, apps: apps, connected: true, preferredBundleID: tile.targetBundleID)
        guard availability.isReady else { reject(availability.message ?? "This action is unavailable."); return }
        let id = UUID()
        if let testCompletion { testCompletions[id] = (tile.name, testCompletion) }
        commandIntervals[id] = signposter.beginInterval("Command acknowledgement")
        busyTiles.insert(tile.id)
        feedback(.soft)
        let timeout: Double = switch tile.action { case .shortcut, .sequence: 310; default: 30 }
        let timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self else { return }
            let test = self.testCompletions.removeValue(forKey: id)
            self.finish(id)
            if let test { test.callback(QuickTileError.timeout.localizedDescription, false) }
            else { self.error = QuickTileError.timeout.localizedDescription; self.clearActivity() }
        }
        pending[id] = (tile.id, timer)
        channel.send(Envelope(id: id, payload: .command(Command(sessionID: sessionID, createdAt: Date().addingTimeInterval(clockOffset), action: tile.action, targetBundleID: tile.agentLauncherBundleID ?? tile.targetBundleID, configuredShortcut: tile.configuredShortcut))))
    }
    func openAgentRequests(_ provider: AgentProvider, source: AgentSource) {
        agentRequestProvider = provider; agentRequestSource = source; agentRequests = []; agentRequestError = nil
        feedback(.soft); refreshAgentRequests()
    }
    func refreshAgentRequests(clearError: Bool = false) {
        if clearError { agentRequestError = nil }
        #if DEBUG
        if uiTest && ProcessInfo.processInfo.arguments.contains("--ui-testing-agent-requests") {
            if agentRequests.isEmpty { agentRequests = [.init(provider:.codex,session:"fixture",kind:.question,title:"Codex needs your input",questions:[.init(id:"app",text:"Which app should be used to create the file?",options:[.init(label:"Xcode",detail:"Create it in the current project"),.init(label:"VS Code")])],canReply:true)] }
            return
        }
        #endif
        guard let provider = agentRequestProvider else { return }
        guard state == .connected, let channel else { agentRequestLoading = false; agentRequestError = "Connect to your Mac."; return }
        guard capabilities.features?.contains("agent-replies.v1") == true else { agentRequestError = "Update the Mac companion to view requests."; return }
        let id = UUID(); agentFetchID = id; agentRequestLoading = true
        channel.send(Envelope(id:id,payload:.agentRequestsRequest(provider,agentRequestSource)))
        agentRequestTimeout?.cancel()
        agentRequestTimeout = Task { [weak self] in
            try? await Task.sleep(for:.seconds(8)); guard !Task.isCancelled, let self, self.agentFetchID == id else { return }
            self.agentFetchID = nil; self.agentRequestLoading = false; self.agentRequestError = "Couldn’t load the request. Try again."
        }
    }
    func replyToAgent(_ request: AgentInputRequest, answers: [String:String] = [:], decision: AgentReplyDecision? = nil) {
        #if DEBUG
        if uiTest && ProcessInfo.processInfo.arguments.contains("--ui-testing-agent-requests") {
            agentRequestProvider = nil; agentRequests = []; capabilities.agents = [.init(provider:.codex,phase:.running)]; return
        }
        #endif
        guard !agentReplyBusy, request.canReply, state == .connected, let sessionID, let channel else { agentRequestError = "This request can’t be answered from this connection."; return }
        let reply = AgentInputReply(sessionID:sessionID,createdAt:Date().addingTimeInterval(clockOffset),requestID:request.id,answers:answers,decision:decision)
        do { try reply.validate() } catch { agentRequestError = error.localizedDescription; return }
        let id = UUID(); agentReplyID = id; agentReplyBusy = true; agentRequestError = nil
        channel.send(Envelope(id:id,payload:.agentReply(reply))); feedback(.rigid)
        agentRequestTimeout?.cancel()
        agentRequestTimeout = Task { [weak self] in
            try? await Task.sleep(for:.seconds(15)); guard !Task.isCancelled, let self, self.agentReplyID == id else { return }
            self.agentReplyID = nil; self.agentReplyBusy = false; self.agentRequestError = "Codex hasn’t confirmed your answer. Check the request on your Mac."
        }
    }
    func closeAgentRequests() {
        agentRequestProvider = nil; agentRequests = []; agentRequestError = nil
        agentRequestTimeout?.cancel(); agentFetchID = nil
    }
    func test(tile: Tile) { execute(tile) }
    func test(tile: Tile, completion: @escaping @MainActor (String, Bool) -> Void) { execute(tile, testCompletion: completion) }
    func enterPreview() {
        guard credentials.isEmpty else { return }
        disconnect(); previewMode = true; allowSaving = false
        var board = DeckPage(name: "Preview", symbol: "cursorarrow")
        board.tiles = [
            Tile(name: "Safari", symbol: "safari", action: .launchApp(bundleID: "com.apple.Safari")),
            Tile(name: "Build", symbol: "hammer", action: .preset("xcode.build")),
            Tile(name: "Cut", symbol: "scissors", action: .preset("finalcut.blade-tool")),
            Tile(name: "Timer", symbol: "timer", action: .timer(seconds: 300)),
            Tile(name: "Play / pause", symbol: "playpause.fill", action: .media(.playPause)),
            Tile(name: "Screenshot", symbol: "viewfinder", action: .system(.screenshotArea))
        ]
        layout = DeckLayout(macID: UUID(), pages: [board]); state = .offline
    }
    func leavePreview() {
        guard previewMode else { return }
        loading = true; layout = nil; loading = false
        previewMode = false; allowSaving = true; clearActivity()
    }
    func cancel(tileID: UUID) {
        guard capabilities.sequenceVersion == 1, let request = pending.first(where: { $0.value.tile == tileID }) else { return }
        channel?.send(Envelope(payload: .cancelCommand(request.key)))
    }
    func selectDisplay(_ id: UInt32) {
        guard state == .connected, capabilities.features?.contains("display-selection.v1") == true else { return }
        channel?.send(Envelope(payload: .selectedDisplay(id)))
    }
    func availability(for action: DeckAction) -> ActionAvailability {
        ActionRegistry.availability(action: action, capabilities: capabilities, apps: apps, connected: state.permitsActions)
    }
    func playbackSymbol(for tile: Tile) -> String {
        guard let target = tile.playbackTarget else { return tile.action.fixedSymbol ?? "playpause.fill" }
        switch capabilities.playback?.first(where: { $0.target == target })?.state ?? .unknown {
        case .playing: return "pause.fill"
        case .paused: return "play.fill"
        case .unknown: return "playpause.fill"
        }
    }
    func addPresetBoard(_ template: PresetBoard, preferredBundleID: String? = nil) {
        let board = template.makePage(apps: apps, preferredBundleID: preferredBundleID)
        if choosingFirstBoard && layout?.pages.count == 1 && layout?.pages.first?.tiles.isEmpty == true { layout?.pages = [board] }
        else { layout?.pages.append(board) }
        choosingFirstBoard = false
    }
    func duplicateTile(_ tile: Tile, boardID: UUID) {
        guard let board = layout?.pages.firstIndex(where: { $0.id == boardID }) else { return }
        var copy = tile; copy.id = UUID()
        layout?.pages[board].tiles.append(copy)
    }
    func duplicateBoard(_ board: DeckPage) {
        guard var copy = BoardPackage(boards: [board]).copies().first else { return }
        copy.name = String((board.name + " copy").prefix(60)); layout?.pages.append(copy)
    }
    func removeTile(_ tile: Tile, boardID: UUID) {
        if assistant.tileID == tile.id { assistant.cancel() }
        guard let board = layout?.pages.firstIndex(where: { $0.id == boardID }), layout?.pages[board].tiles.contains(where: { $0.id == tile.id }) == true else { return }
        rememberRemoval()
        cancel(tileID: tile.id); timers.remove(tile.id)
        layout?.pages[board].removeTile(tile.id)
    }
    func removeBoard(_ id: UUID) {
        guard let board = layout?.pages.first(where: { $0.id == id }) else { return }
        rememberRemoval()
        for tile in board.tiles { cancel(tileID: tile.id); timers.remove(tile.id) }
        layout?.pages.removeAll { $0.id == id }
        if layout?.pages.isEmpty == true { layout?.pages = [DeckPage()] }
    }
    func addPage(boardID: UUID) {
        guard let index = layout?.pages.firstIndex(where: { $0.id == boardID }), let board = layout?.pages[index] else { return }
        layout?.pages[index].tileOrder = board.slots.map { $0?.id } + Array(repeating: nil, count: 8)
        layout?.pages[index].pageNames = (board.pageNames ?? Array(repeating: board.name, count: board.slots.count / 8)) + ["Page \(board.slots.count / 8 + 1)"]
    }
    func duplicatePage(boardID: UUID, index: Int) {
        guard let board = layout?.pages.firstIndex(where: { $0.id == boardID }), var current = layout?.pages[board], index >= 0, index < current.slots.count / 8 else { return }
        let slots = Array(current.slots.dropFirst(index * 8).prefix(8))
        let copies = slots.map { original -> Tile? in guard var tile = original else { return nil }; tile.id = UUID(); return tile }
        var order = current.slots.map { $0?.id }; order.insert(contentsOf: copies.map { $0?.id }, at: (index + 1) * 8)
        var names = current.pageNames ?? Array(repeating: current.name, count: current.slots.count / 8)
        names.insert(String((names[index] + " copy").prefix(100)), at: index + 1)
        current.tiles.append(contentsOf: copies.compactMap { $0 }); current.tileOrder = order; current.pageNames = names
        layout?.pages[board] = current
    }
    func removePage(boardID: UUID, index: Int) {
        guard let board = layout?.pages.firstIndex(where: { $0.id == boardID }), var current = layout?.pages[board], current.slots.count > 8, index >= 0, index < current.slots.count / 8 else { return }
        rememberRemoval()
        var order = current.slots.map { $0?.id }
        let removed = Set(order[(index * 8)..<((index + 1) * 8)].compactMap { $0 })
        for tileID in removed { cancel(tileID: tileID); timers.remove(tileID) }
        order.removeSubrange((index * 8)..<((index + 1) * 8)); current.tileOrder = order
        current.tiles.removeAll { removed.contains($0.id) }
        if current.pageNames?.indices.contains(index) == true { current.pageNames?.remove(at: index) }
        layout?.pages[board] = current
    }
    func moveTile(_ tile: Tile, from sourceID: UUID, to destinationID: UUID, slot: Int) {
        guard var layout, let source = layout.pages.firstIndex(where: { $0.id == sourceID }), let destination = layout.pages.firstIndex(where: { $0.id == destinationID }), layout.pages[destination].slots.indices.contains(slot) else { return }
        if source == destination { layout.pages[source].place(tile.id, at: slot) }
        else {
            let displaced = layout.pages[destination].slots[slot]
            let origin = layout.pages[source].slots.firstIndex { $0?.id == tile.id }
            layout.pages[source].removeTile(tile.id); layout.pages[destination].tiles.append(tile)
            if let displaced, let origin { layout.pages[destination].removeTile(displaced.id); layout.pages[source].tiles.append(displaced); layout.pages[source].place(displaced.id, at: origin) }
            layout.pages[destination].place(tile.id, at: slot)
        }
        self.layout = layout; feedback(.selection)
    }
    func undoRemoval() {
        guard let backup = removalHistory.last, var current = layout, backup.macID == current.macID else { return }
        removalHistory.removeLast()
        current.pages = backup.pages; layout = current
        undoAvailable = !removalHistory.isEmpty; feedback(.selection)
    }
    private func rememberRemoval() {
        guard let layout else { return }
        removalHistory.append(layout)
        undoAvailable = true
    }
    func clearRemovalHistory() {
        removalHistory.removeAll()
        undoAvailable = false
    }
    func exportBoards(boardID: UUID? = nil) async throws -> Data {
        guard let layout else { throw QuickTileError.invalid("No board to export.") }
        let boards = layout.pages.filter { boardID == nil || $0.id == boardID }
        let references = Set(boards.flatMap { [$0.customIconReference] + $0.tiles.map(\.customIconReference) }.compactMap { $0 })
        let assets = try await images.exportCustomAssets(references: references)
        return try await Task.detached(priority: .utility) { try BoardPackage(boards: boards, assets: assets).encoded() }.value
    }
    func importBoards(_ data: Data) async throws {
        guard let macID = layout?.macID else { throw QuickTileError.invalid("Choose a Mac first.") }
        let package = try await Task.detached(priority: .utility) { try BoardPackage.decode(data) }.value
        let references = try await images.importCustomAssets(package.assets)
        var copies = package.copies()
        for board in copies.indices {
            if let old = copies[board].customIconReference { copies[board].customIconReference = references[old] }
            for tile in copies[board].tiles.indices {
                if let old = copies[board].tiles[tile].customIconReference { copies[board].tiles[tile].customIconReference = references[old] }
                // Target choices belong to the exporting Mac. Rebind locally or leave repairable.
                if let old = copies[board].tiles[tile].targetBundleID {
                    copies[board].tiles[tile].targetBundleID = AppProfiles.resolve(bundleID: old, apps: apps)?.id ?? old
                }
            }
        }
        guard layout?.macID == macID else { throw QuickTileError.invalid("The selected Mac changed. Import again.") }
        layout?.pages.append(contentsOf: copies)
    }
    private func pumpIcons() {
        guard state == .connected, let channel else { return }
        for key in iconQueue.expire() { images.failed(key) }
        while let request = iconQueue.next() {
            channel.send(Envelope(id: request.id, payload: .iconRequest(version: request.key)))
        }
    }
    private func installCatalog(apps: [AppEntry], shortcuts: [ShortcutEntry]) {
        guard self.apps != apps || self.shortcuts != shortcuts else { return }
        appByID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        self.apps = apps; self.shortcuts = shortcuts; catalogRevision = UUID()
    }
    func updateIdleTimer() { UIApplication.shared.isIdleTimerDisabled = foreground && state == .connected && layout?.settings.keepAwake == true }
    private func persist() {
        updateIdleTimer()
        updateDialPolling()
        guard !loading, allowSaving, let layout else { return }
        timers.setNotificationsEnabled(layout.settings.timerNotifications == true)
        layoutRevision += 1
        let revision = layoutRevision
        saveTask?.cancel()
        saveTask = Task { [weak self, writer] in
            do {
                try await Task.sleep(for: .milliseconds(200))
                try Task.checkCancellation()
                try await writer.save(layout)
            } catch is CancellationError { }
            catch {
                guard let self, self.layoutRevision == revision else { return }
                self.error = "Could not save your board: \(error.localizedDescription)"
            }
        }
    }
    private func flushLayout() {
        saveTask?.cancel()
        guard !loading, allowSaving, let layout else { return }
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save boards", expirationHandler: nil)
        saveTask = Task { [weak self, writer] in
            defer { if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) } }
            do { try await writer.save(layout) }
            catch { self?.error = "Could not save your board: \(error.localizedDescription)" }
        }
    }
    private func connectIfPossible() {
        guard foreground, !uiTest, channel == nil, reconnect == nil else { return }
        let identity: UUID, key: Data
        if let invite {
            guard invite.expiresAt > Date() else { self.invite = nil; pairingStage = .expired; error = "Pairing expired. Generate a new QR on the Mac."; state = .offline; return }
            identity = invite.identity; key = invite.key
        } else if let selected { identity = selected.id; key = selected.key }
        else { state = .searching; return }
        // Resolve the stable Bonjour identity, including after service address/port changes.
        let endpoint = nearby.first(where: { $0.id == identity.uuidString })?.endpoint
            ?? NWEndpoint.service(name: identity.uuidString, type: Limits.service, domain: "local.", interface: nil)
        do {
            let channel = WireChannel(NWConnection(to: endpoint, using: try SecureTransport.parameters(key: key, identity: identity)))
            self.channel = channel; state = .connecting
            channel.onReady = { [weak self, weak channel] in
                guard let self, let channel else { return }
                let hello = Hello(name: String(UIDevice.current.name.prefix(100)), features: ["structured-results.v1", "sequences.v1", "frontmost-app.v1", "display-selection.v1", "agent-health.v1", "playback-state.v1", "media-player-adapters.v1", "voice-assistant.v1", "agent-replies.v1"])
                channel.send(Envelope(payload: self.invite == nil ? .hello(hello) : .pairRequest(hello)))
                if self.invite != nil { self.state = .awaitingApproval; self.pairingStage = .awaitingApproval }
                self.heartbeat = Task { [weak channel] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(15))
                        guard !Task.isCancelled, let channel, !channel.isClosed else { return }
                        channel.send(Envelope(payload: .ping))
                    }
                }
            }
            channel.onMessage = { [weak self] message in self?.receive(message) }
            channel.onClose = { [weak self, weak channel] reason in
                guard let self, self.channel === channel else { return }
                self.channel = nil; self.sessionID = nil; self.heartbeat?.cancel(); self.authTimeout?.cancel()
                self.iconPump?.cancel(); self.iconQueue.reconnect()
                self.assistant.cancel()
                self.state = .offline; self.updateIdleTimer(); self.failOutstanding()
                self.controls.setAvailable(false)
                if reason.localizedCaseInsensitiveContains("paused") { self.macPaused = true }
                let pairingFailed = self.invite != nil
                if pairingFailed { self.pairingStage = (self.invite?.expiresAt ?? .distantPast) <= Date() ? .expired : .failed; self.error = reason }
                if self.foreground { if !pairingFailed { self.clearActivity() }; self.scheduleReconnect() }
            }
            channel.start()
            authTimeout = Task { [weak self, weak channel] in
                try? await Task.sleep(for: .seconds(self?.invite == nil ? 15 : 125))
                if !Task.isCancelled { channel?.close("Authentication or approval timed out.") }
            }
        } catch { self.error = error.localizedDescription; state = .offline }
    }
    private func receive(_ message: Envelope) {
        switch message.payload {
        case .paired(let credential):
            guard let invite, invite.macID == credential.macID, invite.expiresAt > Date(), credential.key.count == 32 else { channel?.close("Invalid pairing response."); return }
            do {
                let updated = credentials.filter { $0.macID != credential.macID } + [credential]
                try vault.write(updated, account: "macs"); credentials = updated
                self.invite = nil; select(credential); pairingStage = .approved; newlyPaired = true; setActivity("Paired"); feedback(.success)
            } catch { self.error = error.localizedDescription; disconnect() }
        case .welcome(let welcome):
            guard invite == nil, selected?.macID == welcome.macID, sessionID == nil else { channel?.close("Mac identity did not match the saved credential."); return }
            sessionID = welcome.sessionID; macPaused = false; clockOffset = welcome.serverTime.timeIntervalSinceNow
            capabilities = welcome.capabilities; state = .connected; backoff = 1; authTimeout?.cancel(); activity = nil; error = nil
            frontmostBundleID = capabilities.frontmostBundleID
            if newlyPaired { newlyPaired = false; choosingFirstBoard = layout?.pages.allSatisfy { $0.tiles.isEmpty } == true }
            controls.setAvailable(capabilities.controlsVersion == 1)
            updateIdleTimer(); refreshCatalog()
            images.retryAppRequests()
            pumpIcons()
            iconPump?.cancel()
            iconPump = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }; self?.pumpIcons()
                }
            }
        case .catalog(let chunk):
            guard state == .connected else { channel?.close("Catalog before authentication."); return }
            if chunk.index == 0 { generation = chunk.generation; incomingApps = []; incomingShortcuts = []; nextCatalogIndex = 0 }
            guard generation == chunk.generation, chunk.index == nextCatalogIndex else { channel?.close("Incomplete app catalog. Reconnecting."); return }
            incomingApps.append(contentsOf: chunk.apps); incomingShortcuts.append(contentsOf: chunk.shortcuts); nextCatalogIndex += 1
            if chunk.isLast {
                installCatalog(apps: incomingApps, shortcuts: incomingShortcuts); catalogNote = chunk.note
                incomingApps = []; incomingShortcuts = []
                if let selected {
                    let snapshot = CatalogSnapshot(apps: apps, shortcuts: shortcuts), destination = catalogURL(selected.macID), cache = cache
                    Task.detached(priority: .utility) {
                        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: destination, options: .atomic) }
                        Self.pruneIconCache(at: cache)
                    }
                }
            }
        case .icon(let asset):
            guard state == .connected, iconQueue.key(for: message.id) == asset.version else { return }
            Task {
                if await images.receive(asset) { _ = iconQueue.complete(message.id) }
                else if let exhausted = iconQueue.fail(message.id) { images.failed(exhausted) }
                pumpIcons()
            }
        case .agentRequests(let requests):
            guard state == .connected, message.id == agentFetchID else { return }
            agentFetchID = nil; agentRequestLoading = false; agentRequestTimeout?.cancel()
            agentRequests = Array(requests.filter { $0.provider == agentRequestProvider }.prefix(24))
        case .result(let result):
            if message.id == agentReplyID {
                guard result.status != .accepted else { return }
                agentReplyID = nil; agentReplyBusy = false; agentRequestTimeout?.cancel()
                if result.status == .completed { agentRequestProvider = nil; agentRequests = []; setActivity("Answered Codex"); feedback(.success) }
                else { agentRequestError = result.message; feedback(.error) }
                return
            }
            if let callback = assistantCompletions[message.id] {
                if result.status != .accepted {
                    assistantCompletions.removeValue(forKey: message.id); finish(message.id)
                    callback(result.message, result.status == .completed && result.outcome != .cancelled)
                }
                return
            }
            if controls.receiveError(id: message.id, result: result) { feedback(.error); return }
            if iconQueue.key(for: message.id) != nil {
                if let exhausted = iconQueue.fail(message.id) { images.failed(exhausted) }
                pumpIcons(); return
            }
            guard pending[message.id] != nil else { return }
            if result.status == .accepted, let interval = commandIntervals.removeValue(forKey: message.id) {
                signposter.endInterval("Command acknowledgement", interval)
            }
            if let progress = result.sequenceProgress, let tile = pending[message.id]?.tile { sequenceProgress[tile] = progress }
            if result.status != .accepted {
                guard let request = pending[message.id] else { return }
                let test = testCompletions.removeValue(forKey: message.id)
                let title = test?.title ?? layout?.pages.lazy.flatMap(\.tiles).first(where: { $0.id == request.tile })?.name ?? "Action"
                finish(message.id)
                if let test {
                    let succeeded = result.status == .completed && result.outcome != .cancelled
                    test.callback(result.status == .completed ? compactSuccess(for: title, result: result) : result.message, succeeded)
                    if !succeeded { feedback(.error) }
                    return
                }
                if result.status == .completed {
                    setActivity(compactSuccess(for: title, result: result))
                    if result.outcome == .opened || result.outcome == .stateChanged || result.outcome == .shortcutCompleted { feedback(.success) }
                }
                else { clearActivity() }
                if result.status == .failed { error = result.message }
            }
        case .controls(let value): if state == .connected { controls.receive(id: message.id, value: value) }
        case .capabilities(let value):
            if state == .connected, capabilities != value {
                capabilities = value
                frontmostBundleID = value.frontmostBundleID
                controls.setAvailable(value.controlsVersion == 1)
            }
        case .pong: break
        case .closed(let reason): channel?.close(reason)
        default: channel?.close("Unexpected protocol message.")
        }
    }
    private func scheduleReconnect() {
        guard foreground, selected != nil || invite != nil, reconnect == nil else { return }
        let delay = backoff; backoff = min(backoff * 2, 30)
        reconnect = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.reconnect = nil; self.connectIfPossible()
        }
    }
    private func disconnect() {
        agentRequests = []; agentRequestLoading = false; agentReplyBusy = false
        agentFetchID = nil; agentReplyID = nil; agentRequestTimeout?.cancel()
        if agentRequestProvider != nil { agentRequestError = "Mac disconnected." }
        assistant.cancel()
        controls.setAvailable(false)
        reconnect?.cancel(); reconnect = nil; heartbeat?.cancel(); heartbeat = nil; authTimeout?.cancel(); authTimeout = nil
        iconPump?.cancel(); iconPump = nil; iconQueue.reconnect()
        let old = channel; channel = nil; old?.close(); sessionID = nil; failOutstanding(); state = .offline; updateIdleTimer()
    }
    private func finish(_ id: UUID) {
        if let interval = commandIntervals.removeValue(forKey: id) { signposter.endInterval("Command acknowledgement", interval) }
        if let value = pending.removeValue(forKey: id) { value.timer.cancel(); busyTiles.remove(value.tile); sequenceProgress.removeValue(forKey: value.tile) }
    }
    private func setActivity(_ message: String) {
        guard activity != message else { return }
        activityID = UUID(); activityTask?.cancel(); activity = message
        let id = activityID
        activityTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled, let self, self.activityID == id else { return }
            self.activity = nil
        }
    }
    private func clearActivity() {
        activityID = UUID(); activityTask?.cancel(); activityTask = nil
        activity = nil
    }
    private func compactSuccess(for title: String, result: ActionResult) -> String {
        switch result.outcome {
        case .opened: return "Opened \(title)"
        case .commandSent, nil: return "Sent \(title)"
        case .shortcutCompleted: return "Ran \(title)"
        case .stateChanged: return "Updated \(title)"
        case .sequenceCompleted: return "Finished \(title)"
        case .cancelled: return "Stopped \(title)"
        }
    }
    private func failOutstanding() {
        if pending.keys.contains(where: { testCompletions[$0] == nil }) { error = QuickTileError.disconnected.localizedDescription }
        for id in Array(pending.keys) {
            let callback = assistantCompletions.removeValue(forKey: id)
            callback?(QuickTileError.disconnected.localizedDescription, false)
            let test = testCompletions.removeValue(forKey: id)
            finish(id)
            test?.callback(QuickTileError.disconnected.localizedDescription, false)
        }
    }
    private struct CatalogSnapshot: Codable, Sendable { let apps: [AppEntry]; let shortcuts: [ShortcutEntry] }
    private func catalogURL(_ id: UUID) -> URL { cache.appendingPathComponent(id.uuidString + ".catalog.json") }
    nonisolated private static func pruneIconCache(at cache: URL) {
        // Content hashes are global. Bound disk use without ever deleting layouts or Keychain items.
        guard let files = try? FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        let sorted = files.filter { !$0.lastPathComponent.hasPrefix("custom-") }.sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        var size = 0
        for file in sorted { size += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0; if size > 128 * 1024 * 1024 { try? FileManager.default.removeItem(at: file) } }
    }
}

@MainActor final class TileTimerStore: ObservableObject {
    @Published private(set) var values: [UUID: TileCountdown] = [:]
    private var lastReminder = Date.distantPast
    private let persistence = TimerPersistence(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QuickTile/Timers", isDirectory: true))
    private var macID: UUID?
    private var loadTask: Task<Void, Never>?
    private var notificationsEnabled = false
    private var notificationPermission = false
    private var generation = UUID()
    var onError: ((String) -> Void)?
    func selectMac(_ id: UUID) {
        loadTask?.cancel(); generation = UUID(); macID = id; values = [:]
        let generation = generation
        loadTask = Task { [weak self, persistence] in
            do {
                let restored = try await persistence.load(macID: id)
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                self.values.merge(restored) { current, _ in current }
                self.syncNotifications()
            } catch { self?.onError?("Could not restore timers: \(error.localizedDescription)") }
        }
    }
    func setNotificationsEnabled(_ enabled: Bool) {
        guard notificationsEnabled != enabled else { return }
        notificationsEnabled = enabled
        if enabled {
            Task { [weak self] in
                do {
                    let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                    guard let self else { return }
                    self.notificationPermission = allowed
                    if !allowed { self.onError?("Timer notifications are off. Enable them in iPhone Settings.") }
                    self.syncNotifications()
                } catch { self?.onError?(error.localizedDescription) }
            }
        } else { syncNotifications() }
    }
    func value(_ id: UUID, seconds: Int) -> TileCountdown {
        guard let value = values[id], value.duration == seconds else { return TileCountdown(seconds: seconds) }
        return value
    }
    func toggle(_ id: UUID, seconds: Int) {
        var timer = value(id, seconds: seconds)
        timer.toggle(at: Date()); values[id] = timer
        persist(); syncNotifications()
    }
    func reset(_ id: UUID, seconds: Int) { values[id] = TileCountdown(seconds: seconds); persist(); syncNotifications() }
    func remove(_ id: UUID) {
        values.removeValue(forKey: id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID(id)])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationID(id)])
        persist()
    }
    private func notificationID(_ id: UUID) -> String { "quicktile.timer.\(macID?.uuidString ?? "local").\(id.uuidString)" }
    private func persist() {
        guard let macID else { return }
        let values = values
        Task { [weak self, persistence] in
            do { try await persistence.save(values, macID: macID) }
            catch { self?.onError?("Could not save timers: \(error.localizedDescription)") }
        }
    }
    private func syncNotifications() {
        let center = UNUserNotificationCenter.current()
        for (id, timer) in values {
            let identifier = notificationID(id)
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            guard notificationsEnabled, notificationPermission, let deadline = timer.deadline, deadline > Date() else {
                if !timer.finished { center.removeDeliveredNotifications(withIdentifiers: [identifier]) }
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = "Timer finished"; content.body = "Open QuickTile to acknowledge your timer."; content.sound = .default
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false))
            center.add(request)
        }
    }
    func tick(tiles: [Tile], haptic: (UUID, TimerHapticPattern) -> Void) {
        let durations = Dictionary(uniqueKeysWithValues: tiles.compactMap { tile -> (UUID, Int)? in
            guard case .timer(let seconds) = tile.action else { return nil }
            return (tile.id, seconds)
        })
        let now = Date()
        var updated = values.filter { durations[$0.key] == $0.value.duration }
        for id in Array(updated.keys) { updated[id]?.update(at: now) }
        if updated != values {
            let structuralChange = updated.count != values.count || updated.contains { values[$0.key]?.finished != $0.value.finished }
            let removed = Set(values.keys).subtracting(updated.keys)
            for id in removed { remove(id) }
            values = updated
            if structuralChange { persist(); syncNotifications() }
        }
        if let tile = tiles.first(where: { updated[$0.id]?.finished == true && $0.timerHaptic != .off }), UIApplication.shared.applicationState == .active {
            let pattern = tile.timerHaptic ?? .click
            if now.timeIntervalSince(lastReminder) >= pattern.interval {
                lastReminder = now
                haptic(tile.id, pattern)
            }
        }
    }
}
