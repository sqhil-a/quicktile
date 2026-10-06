import XCTest
import Network
import Security
@testable import QuickTileCore

final class TransportTests: XCTestCase {
    @MainActor func testRealTLSEncryptedRoundTripAndWrongKeyRejection() async throws {
        let identity = UUID(), key = try SecureRandom.key()
        let serverParameters = try SecureTransport.parameters(key: key, identity: identity)
        serverParameters.prohibitedInterfaceTypes = [] // Explicit loopback exception confined to tests.
        let listener = try NWListener(using: serverParameters, on: .any)
        let listening = expectation(description: "Listening")
        listener.stateUpdateHandler = { state in if case .ready = state { listening.fulfill() } }
        var serverChannels: [WireChannel] = []
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                let peer = WireChannel(connection); serverChannels.append(peer)
                peer.onMessage = { message in peer.send(Envelope(id: message.id, payload: .result(.init(.completed, "Encrypted response")))) }
                peer.start()
            }
        }
        listener.start(queue: .main)
        await fulfillment(of: [listening], timeout: 5)
        guard let port = listener.port else { XCTFail("No listener port"); return }
        let params = try SecureTransport.parameters(key: key, identity: identity); params.prohibitedInterfaceTypes = []
        let good = WireChannel(NWConnection(host: "127.0.0.1", port: port, using: params))
        let response = expectation(description: "Authenticated response")
        let requestID = UUID()
        good.onReady = {
            guard let metadata = good.connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else { XCTFail("Missing TLS metadata"); return }
            XCTAssertEqual(sec_protocol_metadata_get_negotiated_tls_protocol_version(metadata.securityProtocolMetadata), .TLSv12)
            good.send(Envelope(id: requestID, payload: .hello(Hello(name: "Integration test"))))
        }
        good.onMessage = { message in
            XCTAssertEqual(message.id, requestID)
            if case .result(let result) = message.payload { XCTAssertEqual(result.status, .completed); response.fulfill() }
        }
        good.start(); await fulfillment(of: [response], timeout: 10)
        let badParams = try SecureTransport.parameters(key: SecureRandom.key(), identity: identity); badParams.prohibitedInterfaceTypes = []
        let bad = WireChannel(NWConnection(host: "127.0.0.1", port: port, using: badParams))
        let rejected = expectation(description: "Wrong key rejected")
        bad.onReady = { XCTFail("Wrong key must never authenticate") }
        bad.onClose = { _ in rejected.fulfill() }
        bad.start(); await fulfillment(of: [rejected], timeout: 20)
        good.close(); bad.close(); serverChannels.forEach { $0.close() }; listener.cancel()
    }
}
