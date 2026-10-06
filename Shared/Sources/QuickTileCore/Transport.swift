import Foundation
@preconcurrency import Network
import Security

public enum SecureTransport {
    public static func parameters(key: Data, identity: UUID) throws -> NWParameters {
        guard key.count == 32 else { throw QuickTileError.invalid("A TLS credential must contain 256 random bits.") }
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        // RFC 4279 / RFC 5487, implemented entirely by Apple's TLS stack. No certificate bypass.
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        key.withUnsafeBytes { keyBytes in
            Data(identity.uuidString.utf8).withUnsafeBytes { identityBytes in
                sec_protocol_options_add_pre_shared_key(options, DispatchData(bytes: keyBytes) as __DispatchData, DispatchData(bytes: identityBytes) as __DispatchData)
            }
        }
        sec_protocol_options_set_tls_tickets_enabled(options, false)
        sec_protocol_options_set_tls_resumption_enabled(options, false)
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 10
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 20
        tcp.keepaliveInterval = 10
        tcp.keepaliveCount = 3
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = false
        // Discovery uses LAN Bonjour. Do not restrict to Wi-Fi: the Mac can use Ethernet.
        parameters.prohibitedInterfaceTypes = [.cellular, .loopback]
        return parameters
    }
}

/// Length-prefixed JSON over authenticated TLS. Every channel is owned on the main actor.
@MainActor public final class WireChannel {
    public let id = UUID()
    public let connection: NWConnection
    public var onReady: (() -> Void)?
    public var onMessage: ((Envelope) -> Void)?
    public var onClose: ((String) -> Void)?
    public private(set) var isReady = false
    public private(set) var isClosed = false
    private var watchdog: Task<Void, Never>?
    private var lastReceived = Date()
    private var outgoingBytes = 0
    public init(_ connection: NWConnection) { self.connection = connection }
    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, !self.isClosed else { return }
                switch state {
                case .ready: self.isReady = true; self.lastReceived = Date(); self.receiveHeader(); self.onReady?()
                case .failed(let error): self.close("Connection failed: \(error.localizedDescription)")
                case .waiting(let error): self.close("Network unavailable: \(error.localizedDescription). Check Local Network permission and Wi-Fi.")
                case .cancelled: self.close("Disconnected")
                default: break
                }
            }
        }
        connection.start(queue: .main)
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, !self.isClosed else { return }
                if Date().timeIntervalSince(self.lastReceived) > (self.isReady ? 45 : 15) {
                    self.close("Connection timed out. Check that the Mac is awake and on the same network."); return
                }
            }
        }
    }
    public func send(_ envelope: Envelope) {
        guard isReady, !isClosed else { return }
        do {
            let data = try envelope.encoded()
            guard outgoingBytes + data.count <= Limits.frameBytes * 4 else { close("Peer is receiving too slowly."); return }
            var length = UInt32(data.count).bigEndian
            var frame = withUnsafeBytes(of: &length) { Data($0) }
            frame.append(data)
            outgoingBytes += data.count
            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                Task { @MainActor in
                    self?.outgoingBytes -= data.count
                    if let error { self?.close("Send failed: \(error.localizedDescription)") }
                }
            })
        } catch { close(error.localizedDescription) }
    }
    public func close(_ reason: String = "Disconnected", notifyingPeer: Bool = false) {
        guard !isClosed else { return }
        var finalFrame: Data?
        if notifyingPeer, isReady, let data = try? Envelope(payload: .closed(String(reason.prefix(1_000)))).encoded() {
            var length = UInt32(data.count).bigEndian
            finalFrame = withUnsafeBytes(of: &length) { Data($0) }
            finalFrame?.append(data)
        }
        isClosed = true; isReady = false
        watchdog?.cancel(); watchdog = nil
        connection.stateUpdateHandler = nil
        if let finalFrame {
            // Revoke local work immediately, but let the authenticated terminal message
            // drain before cancelling the socket. A local close reason alone is never
            // visible on the other device.
            let connection = connection
            connection.send(content: finalFrame, contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { error in if error != nil { connection.cancel() } })
            Task { try? await Task.sleep(for: .seconds(1)); connection.cancel() }
        } else { connection.cancel() }
        let callback = onClose
        onReady = nil; onMessage = nil; onClose = nil
        callback?(reason)
    }
    private func receiveHeader() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, !self.isClosed else { return }
                guard error == nil, let data, data.count == 4 else { self.close("The Mac disconnected."); return }
                let size = data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                guard size > 0, size <= Limits.frameBytes else { self.close("Invalid message length."); return }
                if complete { self.close("Incomplete message."); return }
                self.receiveBody(Int(size))
            }
        }
    }
    private func receiveBody(_ size: Int) {
        connection.receive(minimumIncompleteLength: size, maximumLength: size) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, !self.isClosed else { return }
                guard error == nil, let data, data.count == size else { self.close("Incomplete message."); return }
                do {
                    let envelope = try Envelope.decode(data)
                    self.lastReceived = Date()
                    if case .ping = envelope.payload { self.send(Envelope(id: envelope.id, payload: .pong)) }
                    else { self.onMessage?(envelope) }
                    if complete { self.close("Disconnected") } else if !self.isClosed { self.receiveHeader() }
                } catch { self.close("Invalid protocol message: \(error.localizedDescription)") }
            }
        }
    }
}

public struct NearbyMac: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let endpoint: NWEndpoint
    public init(id: String, name: String, endpoint: NWEndpoint) { self.id = id; self.name = name; self.endpoint = endpoint }
}
@MainActor public final class Discovery {
    public var onChange: (([NearbyMac]) -> Void)?
    public var onState: ((ConnectionState, String?) -> Void)?
    private var browser: NWBrowser?
    public init() {}
    public func start() {
        guard browser == nil else { return }
        let params = NWParameters.tcp
        params.includePeerToPeer = false
        params.prohibitedInterfaceTypes = [.cellular, .loopback]
        let browser = NWBrowser(for: .bonjour(type: Limits.service, domain: "local."), using: params)
        self.browser = browser
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.onState?(.searching, nil)
                case .waiting(let error), .failed(let error):
                    let denied = error == .dns(-65570)
                    self?.onState?(denied ? .permissionDenied : .offline, denied ? "Allow QuickTile in Settings → Privacy & Security → Local Network." : error.localizedDescription)
                default: break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let macs = results.compactMap { result -> NearbyMac? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                var displayName = "QuickTile Mac"
                if case .bonjour(let record) = result.metadata, let value = record["name"] { displayName = String(describing: value) }
                return NearbyMac(id: name, name: displayName, endpoint: result.endpoint)
            }.sorted { $0.name < $1.name }
            Task { @MainActor in self?.onChange?(macs) }
        }
        browser.start(queue: .main)
    }
    public func stop() { browser?.cancel(); browser = nil; onChange?([]) }
}
