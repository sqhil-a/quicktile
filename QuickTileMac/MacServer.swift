import AppKit
import Combine
import Network
import QuickTileCore

@MainActor final class MacServer: ObservableObject {
    @Published private(set) var devices: [Credential] = []
    @Published private(set) var invite: PairingInvite?
    @Published private(set) var pending: [PendingPair] = []
    @Published private(set) var connectedNames: [String] = []
    @Published private(set) var paused = false
    @Published private(set) var status = "Starting"
    @Published var error: String?
    @Published private(set) var refreshing = false
    @Published private(set) var appCount = 0
    let macID: UUID
    let catalog = Catalog()
    let agentStatus = AgentStatusStore()
    let assistant: GroqAssistant
    lazy var executor = ActionExecutor(catalog: catalog, agents: agentStatus)
    var macName: String { String((Host.current().localizedName ?? "My Mac").prefix(100)) }
    private let vault: KeychainStore
    #if DEBUG
    var testAllowsLoopback = false
    func testPort(_ identity: UUID) -> NWEndpoint.Port? {
        guard let listener = listeners[identity], case .ready = listener.state else { return nil }
        return listener.port
    }
    #endif
    private var listeners: [UUID: NWListener] = [:]
    private var peers: [UUID: Peer] = [:]
    private var heartbeat: Task<Void, Never>?
    private var expiry: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var suspended = false
    private var lastInvite = Date.distantPast

    struct PendingPair: Identifiable { let id: UUID; let name: String; let expiresAt: Date }
    final class Peer {
        let channel: WireChannel
        let identity: UUID
        let pairing: Bool
        var gate = CommandGate()
        var name = "iPhone"
        var tasks: [UUID: Task<Void, Never>] = [:]
        var requestsThisWindow = 0
        var windowStart = Date()
        var catalogTask: Task<Void, Never>?
        var features = Set<String>()
        var lastCapabilities: Capabilities?
        var displayID: UInt32?
        init(channel: WireChannel, identity: UUID, pairing: Bool) { self.channel = channel; self.identity = identity; self.pairing = pairing }
    }
    init(vault: KeychainStore = KeychainStore(service: "sahil.QuickTile.Mac.credentials"), defaults: UserDefaults = .standard, assistant: GroqAssistant? = nil) {
        self.assistant = assistant ?? GroqAssistant()
        self.vault = vault
        if let saved = defaults.string(forKey: "macID"), let id = UUID(uuidString: saved) { macID = id }
        else { macID = UUID(); defaults.set(macID.uuidString, forKey: "macID") }
        do { devices = try vault.read([Credential].self, account: "devices") ?? [] }
        catch { self.error = error.localizedDescription }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.suspend() } })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.resumeAfterWake() } })
        for event in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(center.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.refresh() } })
        }
        start()
        Task { await refresh() }
    }
    func start() {
        guard !paused, !suspended else { return }
        for credential in devices where listeners[credential.id] == nil {
            do { try listen(identity: credential.id, key: credential.key, pairing: false) }
            catch { self.error = error.localizedDescription }
        }
        status = devices.isEmpty ? "Ready to pair" : "Waiting for your iPhone"
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                for peer in self.peers.values {
                    peer.channel.send(Envelope(payload: .ping))
                    if peer.gate.authorized {
                        let capabilities = self.capabilities(for: peer)
                        if peer.lastCapabilities != capabilities { peer.lastCapabilities = capabilities; peer.channel.send(Envelope(payload: .capabilities(capabilities))) }
                    }
                }
            }
        }
    }
    func createInvite() {
        guard !paused, !suspended else { error = "Resume QuickTile before pairing."; return }
        guard Date().timeIntervalSince(lastInvite) >= 3 else { error = "Wait a moment before generating another QR."; return }
        cancelInvite()
        do {
            let invite = PairingInvite(macID: macID, name: macName, key: try SecureRandom.key())
            try listen(identity: invite.identity, key: invite.key, pairing: true)
            self.invite = invite; lastInvite = Date()
            expiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(120))
                if !Task.isCancelled { self?.cancelInvite() }
            }
        } catch { self.error = error.localizedDescription }
    }
    func cancelInvite() {
        expiry?.cancel(); expiry = nil
        if let invite {
            listeners.removeValue(forKey: invite.identity)?.cancel()
            for peer in Array(peers.values) where peer.identity == invite.identity { peer.channel.close("Pairing invitation expired or was cancelled.", notifyingPeer: true) }
        }
        invite = nil; pending = []
    }
    func approve(_ request: PendingPair) {
        guard let peer = peers[request.id], let invite, invite.identity == peer.identity, invite.expiresAt > Date(), !paused else { error = "Pairing request expired."; return }
        do {
            let credential = Credential(macID: macID, name: request.name, key: try SecureRandom.key())
            let next = devices + [credential]
            try vault.write(next, account: "devices")
            devices = next
            try listen(identity: credential.id, key: credential.key, pairing: false)
            var forPhone = credential; forPhone.name = macName
            peer.channel.send(Envelope(payload: .paired(forPhone)))
            // Consume the invitation immediately. Keep only the response channel long enough to flush.
            listeners.removeValue(forKey: invite.identity)?.cancel()
            self.invite = nil; pending = []; expiry?.cancel(); expiry = nil
            for other in Array(peers.values) where other.pairing && other.channel.id != peer.channel.id { other.channel.close("Invitation already used.", notifyingPeer: true) }
            Task { try? await Task.sleep(for: .seconds(2)); peer.channel.close("Pairing approved. Reconnect using the new credential.") }
        } catch { self.error = error.localizedDescription }
    }
    func deny(_ request: PendingPair) { peers[request.id]?.channel.close("Pairing was declined on the Mac.", notifyingPeer: true); pending.removeAll { $0.id == request.id } }
    func revoke(_ credential: Credential) {
        // Persist first. If Keychain is unavailable, report failure instead of claiming revocation survived restart.
        do {
            let remaining = devices.filter { $0.id != credential.id }
            try vault.write(remaining, account: "devices")
            devices = remaining
            listeners.removeValue(forKey: credential.id)?.cancel()
            for peer in Array(peers.values) where peer.identity == credential.id { peer.gate.revoke(); peer.channel.close("This device was revoked on the Mac.", notifyingPeer: true) }
        } catch { self.error = error.localizedDescription }
    }
    func togglePaused() {
        paused.toggle()
        if paused { stop("QuickTile is paused on the Mac."); status = "Paused" } else { start() }
    }
    func shutdown() { stop("QuickTile quit on the Mac.") }
    func refresh() async {
        guard !refreshing else { return }; refreshing = true
        await catalog.refresh()
        appCount = catalog.apps.count; refreshing = false
        for peer in peers.values where peer.gate.authorized { sendCatalog(peer) }
    }
    private func suspend() { suspended = true; stop("Mac is sleeping."); status = "Sleeping" }
    private func resumeAfterWake() { suspended = false; start(); Task { await refresh() } }
    private func stop(_ reason: String) {
        cancelInvite(); heartbeat?.cancel(); heartbeat = nil
        listeners.values.forEach { $0.cancel() }; listeners = [:]
        for peer in Array(peers.values) { peer.gate.revoke(); peer.channel.close(reason, notifyingPeer: true) }
    }
    private func listen(identity: UUID, key: Data, pairing: Bool) throws {
        let parameters = try SecureTransport.parameters(key: key, identity: identity)
        #if DEBUG
        if testAllowsLoopback { parameters.prohibitedInterfaceTypes = [] }
        #endif
        let listener = try NWListener(using: parameters)
        #if DEBUG
        let shouldAdvertise = !testAllowsLoopback
        #else
        let shouldAdvertise = true
        #endif
        if shouldAdvertise {
            listener.service = NWListener.Service(name: identity.uuidString, type: Limits.service, domain: "local.", txtRecord: NWTXTRecord(["name": macName, "mac": macID.uuidString, "pair": pairing ? "1" : "0"]))
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection, identity: identity, pairing: pairing) }
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor in
                guard let self, let listener, self.listeners[identity] === listener else { return }
                switch state {
                case .failed(let error): self.error = "Local network listener failed: \(error.localizedDescription)"; self.listeners.removeValue(forKey: identity)?.cancel()
                case .waiting(let error): self.status = "Check Local Network permission: \(error.localizedDescription)"
                default: break
                }
            }
        }
        listeners[identity] = listener; listener.start(queue: .main)
    }
    private func accept(_ connection: NWConnection, identity: UUID, pairing: Bool) {
        guard !paused, !suspended, peers.count < 16, listeners[identity] != nil,
              pairing ? (invite?.identity == identity && (invite?.expiresAt ?? .distantPast) > Date()) : devices.contains(where: { $0.id == identity }) else { connection.cancel(); return }
        let channel = WireChannel(connection)
        let actual = Peer(channel: channel, identity: identity, pairing: pairing)
        peers[channel.id] = actual
        channel.onMessage = { [weak self, weak actual] message in
            guard let self, let actual else { return }; self.receive(message, peer: actual)
        }
        channel.onClose = { [weak self, weak actual] _ in
            guard let self, let actual else { return }
            actual.gate.revoke(); actual.tasks.values.forEach { $0.cancel() }; actual.catalogTask?.cancel()
            self.peers.removeValue(forKey: channel.id); self.pending.removeAll { $0.id == channel.id }; self.updateConnections()
        }
        channel.start()
        Task { [weak actual] in
            try? await Task.sleep(for: .seconds(12))
            guard let actual, !actual.gate.authorized else { return }
            if !actual.pairing || !self.pending.contains(where: { $0.id == actual.channel.id }) { actual.channel.close("Authentication timed out.", notifyingPeer: true) }
        }
    }
    private func receive(_ message: Envelope, peer: Peer) {
        guard !paused, !suspended else { peer.channel.close("QuickTile is paused.", notifyingPeer: true); return }
        if Date().timeIntervalSince(peer.windowStart) > 60 { peer.windowStart = Date(); peer.requestsThisWindow = 0 }
        peer.requestsThisWindow += 1
        guard peer.requestsThisWindow < 1200 else { peer.channel.close("Request rate limit exceeded.", notifyingPeer: true); return }
        if case .pong = message.payload { return }
        if peer.pairing {
            guard case .pairRequest(let hello) = message.payload, let invite, invite.identity == peer.identity, invite.expiresAt > Date(), pending.count < 4,
                  !pending.contains(where: { $0.id == peer.channel.id }), (try? Validation.name(hello.name)) != nil else { peer.channel.close("Pairing request rejected.", notifyingPeer: true); return }
            peer.name = hello.name
            pending.append(PendingPair(id: peer.channel.id, name: hello.name, expiresAt: invite.expiresAt))
            status = "Pairing approval needed"
            return
        }
        guard devices.contains(where: { $0.id == peer.identity }) else { peer.channel.close("Device revoked.", notifyingPeer: true); return }
        if case .hello(let hello) = message.payload {
            guard !peer.gate.authorized, (try? Validation.name(hello.name)) != nil else { peer.channel.close("Unexpected greeting.", notifyingPeer: true); return }
            peer.name = hello.name; peer.gate.authorized = true
            peer.features = Set((hello.features ?? []).prefix(32))
            let capabilities = capabilities(for: peer); peer.lastCapabilities = capabilities
            peer.channel.send(Envelope(id: message.id, payload: .welcome(Welcome(macID: macID, name: macName, sessionID: peer.gate.sessionID, capabilities: capabilities))))
            updateConnections(); return
        }
        guard peer.gate.authorized else { peer.channel.close("Authentication required.", notifyingPeer: true); return }
        switch message.payload {
        case .cancelCommand(let id):
            guard peer.features.contains("sequences.v1") || peer.features.contains("voice-assistant.v1") else { return }
            peer.tasks[id]?.cancel()
        case .agentRequestsRequest(let provider, let source):
            guard peer.features.contains("agent-replies.v1") else { return }
            peer.channel.send(Envelope(id:message.id,payload:.agentRequests(agentStatus.requests(provider,source:source))))
        case .agentReply(let reply):
            do {
                guard peer.features.contains("agent-replies.v1") else { throw QuickTileError.unsupported("Update QuickTile to answer agent requests.") }
                try reply.validate()
                try peer.gate.admit(id:message.id,command:.init(sessionID:reply.sessionID,createdAt:reply.createdAt,action:.agent(.codex)))
                guard peer.tasks.count < 4 else { throw QuickTileError.failed("Wait for the current reply to finish.") }
                peer.tasks[message.id] = Task { [weak self, weak peer] in
                    guard let self, let peer else { return }; defer { peer.tasks.removeValue(forKey:message.id) }
                    do {
                        guard peer.gate.authorized, !peer.channel.isClosed, !self.paused else { throw QuickTileError.unauthorized }
                        try await self.agentStatus.controlBridge.reply(reply)
                        peer.channel.send(Envelope(id:message.id,payload:.result(.init(.completed,"Answered",outcome:.commandSent))))
                    } catch { peer.channel.send(Envelope(id:message.id,payload:.result(.init(.failed,error.localizedDescription)))) }
                }
            } catch { peer.channel.send(Envelope(id:message.id,payload:.result(.init(.failed,error.localizedDescription)))) }
        case .assistantRequest(let request):
            do {
                guard peer.features.contains("voice-assistant.v1"), assistant.configured else { throw GroqAssistantError.notConfigured }
                try request.validate()
                try peer.gate.admit(id: message.id, command: .init(sessionID: request.sessionID, createdAt: request.createdAt, action: .assistant))
                guard peer.tasks.count < 4, peers.values.reduce(0, { $0 + $1.tasks.count }) < 8 else { throw GroqAssistantError.busy }
                peer.channel.send(Envelope(id: message.id, payload: .result(.init(.accepted, ""))))
                peer.tasks[message.id] = Task { [weak self, weak peer] in
                    guard let self, let peer else { return }
                    defer { peer.tasks.removeValue(forKey: message.id) }
                    let authorized = { !peer.channel.isClosed && peer.gate.authorized && !self.paused && self.assistant.configured && self.devices.contains { $0.id == peer.identity } }
                    do {
                        let context = AssistantCommandContext(apps: self.catalog.apps, shortcuts: self.catalog.shortcuts,
                            controls: BrightnessControl.shared.snapshot(displayID: peer.displayID), playback: self.executor.capabilities.playback ?? [],
                            frontmostBundleID: self.executor.capabilities.frontmostBundleID)
                        let plans = try await self.assistant.resolve(request.text, context: context)
                        try Task.checkCancellation()
                        guard authorized() else { throw QuickTileError.unauthorized }
                        let result = try await self.executor.executeAssistant(plans, authorized: authorized)
                        peer.channel.send(Envelope(id: message.id, payload: .result(result)))
                        peer.channel.send(Envelope(payload: .controls(BrightnessControl.shared.snapshot(displayID: peer.displayID))))
                    } catch is CancellationError {
                        peer.channel.send(Envelope(id: message.id, payload: .result(.init(.completed, "Stopped", outcome: .cancelled))))
                    } catch { peer.channel.send(Envelope(id: message.id, payload: .result(.init(.failed, error.localizedDescription)))) }
                }
            } catch { peer.channel.send(Envelope(id: message.id, payload: .result(.init(.failed, error.localizedDescription)))) }
        case .selectedDisplay(let id):
            guard peer.features.contains("display-selection.v1"), BrightnessControl.shared.snapshot().displays?.contains(where: { $0.id == id && $0.brightness != nil }) == true else { peer.channel.send(Envelope(id: message.id, payload: .result(.init(.failed, "Choose a supported display.")))); return }
            peer.displayID = id
            peer.channel.send(Envelope(id: message.id, payload: .controls(BrightnessControl.shared.snapshot(displayID: id))))
        case .controlsRequest:
            peer.channel.send(Envelope(id: message.id, payload: .controls(BrightnessControl.shared.snapshot(displayID: peer.displayID))))
        case .adjustControl(let adjustment):
            do {
                try adjustment.validate()
                // Use the same session, timestamp, replay and rate checks as tiles.
                try peer.gate.admit(id: message.id, command: Command(sessionID: adjustment.sessionID, createdAt: adjustment.createdAt, action: .volume(.set(adjustment.value))))
                guard !paused, devices.contains(where: { $0.id == peer.identity }) else { throw QuickTileError.unauthorized }
                switch adjustment.kind {
                case .volume: try VolumeControl().setDialLevel(adjustment.value)
                case .brightness: try BrightnessControl.shared.set(adjustment.value, displayID: adjustment.displayID!)
                }
                peer.channel.send(Envelope(id: message.id, payload: .controls(BrightnessControl.shared.snapshot(displayID: peer.displayID))))
            } catch { peer.channel.send(Envelope(id: message.id, payload: .result(.init(.failed, error.localizedDescription)))) }
        case .catalogRequest:
            sendCatalog(peer)
            Task { await refresh() }
        case .iconRequest(let version):
            if let png = catalog.icon(version: version) { peer.channel.send(Envelope(id: message.id, payload: .icon(IconAsset(version: version, png: png)))) }
            else { peer.channel.send(Envelope(id: message.id, payload: .result(.init(.failed, "Icon changed or unavailable. Refresh the catalog.")))) }
        case .command(let command):
            do {
                if case .sequence = command.action, !peer.features.contains("sequences.v1") { throw QuickTileError.unsupported("Reconnect with an updated QuickTile to run sequences.") }
                if case .media = command.action, command.targetBundleID != nil, !peer.features.contains("media-player-adapters.v1") { throw QuickTileError.unsupported("Reconnect with an updated QuickTile to use player adapters.") }
                try peer.gate.admit(id: message.id, command: command)
                guard peer.tasks.count < 4, peers.values.reduce(0, { $0 + $1.tasks.count }) < 8 else { throw QuickTileError.failed("Mac is busy. Wait for running actions to finish.") }
                peer.channel.send(Envelope(id: message.id, payload: .result(.init(.accepted, "Request accepted; waiting for the Mac."))))
                peer.tasks[message.id] = Task { [weak self, weak peer] in
                    guard let self, let peer else { return }
                    defer { peer.tasks.removeValue(forKey: message.id) }
                    do {
                        let result = try await self.executor.executeCommand(command, authorized: { !peer.channel.isClosed && peer.gate.authorized && !self.paused && self.devices.contains { $0.id == peer.identity } }, progress: { progress in
                            peer.channel.send(Envelope(id: message.id, payload: .result(.init(.accepted, "", sequenceProgress: progress))))
                        })
                        peer.channel.send(Envelope(id: message.id, payload: .result(result)))
                    } catch is CancellationError {
                        peer.channel.send(Envelope(id: message.id, payload: .result(.init(.completed, "Stopped", outcome: .cancelled))))
                    } catch { peer.channel.send(Envelope(id: message.id, payload: .result(.init(.failed, error.localizedDescription)))) }
                }
            } catch { peer.channel.send(Envelope(id: message.id, payload: .result(.init(.failed, error.localizedDescription)))) }
        default: peer.channel.close("Unexpected protocol message.", notifyingPeer: true)
        }
    }
    private func capabilities(for peer: Peer) -> Capabilities {
        var value = executor.capabilities
        if peer.features.contains("agent-replies.v1") { value.features = (value.features ?? []) + ["agent-replies.v1"] }
        if peer.features.contains("voice-assistant.v1") {
            value.features = (value.features ?? []) + ["voice-assistant.v1"]
            value.assistantReady = assistant.configured
        }
        if !peer.features.contains("sequences.v1") { value.sequenceVersion = nil }
        if !peer.features.contains("frontmost-app.v1") { value.frontmostBundleID = nil }
        if !peer.features.contains("playback-state.v1") { value.playback = nil }
        if !peer.features.contains("agent-health.v1") { value.agentSources = nil }
        return value
    }
    private func sendCatalog(_ peer: Peer) {
        guard peer.catalogTask == nil else { return }
        let generation = catalog.generation, apps = catalog.apps, shortcuts = catalog.shortcuts, note = catalog.note
        peer.catalogTask = Task { [weak peer] in
            guard let peer else { return }; defer { peer.catalogTask = nil }
            let count = max(1, max((apps.count + 99) / 100, (shortcuts.count + 99) / 100))
            for index in 0..<count {
                guard !Task.isCancelled, peer.gate.authorized, !peer.channel.isClosed else { return }
                let appSlice = Array(apps.dropFirst(index * 100).prefix(100)), shortcutSlice = Array(shortcuts.dropFirst(index * 100).prefix(100))
                peer.channel.send(Envelope(payload: .catalog(CatalogChunk(generation: generation, index: index, apps: appSlice, shortcuts: shortcutSlice, isLast: index == count - 1, note: note))))
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }
    private func updateConnections() {
        connectedNames = peers.values.filter { $0.gate.authorized }.map(\.name).sorted()
        if !paused { status = connectedNames.isEmpty ? (devices.isEmpty ? "Ready to pair" : "Waiting for your iPhone") : "\(connectedNames.count) connected" }
    }
}
