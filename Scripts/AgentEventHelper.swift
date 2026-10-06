import Foundation
import CryptoKit
import Darwin

/// No UI, transcript storage, network access, or decisions affecting the agent.
@main struct QuickTileAgentEventHelper {
    static func main() {
        guard CommandLine.arguments.count == 2, let provider = AgentProvider(rawValue: CommandLine.arguments[1]) else { return }
        var input = Data()
        while input.count <= 1_048_576 {
            guard let chunk = try? FileHandle.standardInput.read(upToCount: 65_536), !chunk.isEmpty else { break }
            input.append(chunk)
        }
        // Stop requires valid JSON. Interrupt explicitly allows no stdout.
        let name = (try? JSONSerialization.jsonObject(with: input) as? [String: Any])?["hook_event_name"] as? String
        defer { if name == "Stop" { FileHandle.standardOutput.write(Data("{}\n".utf8)) } }
        guard let event = AgentEvent(provider: provider, input: input) else { return }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("QuickTile/AgentStatus", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let identifier = SHA256.hash(data: Data(event.session.utf8)).map { String(format: "%02x", $0) }.joined()
            let url = directory.appendingPathComponent("\(provider.rawValue)-\(identifier).json")
            let lock = open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR, 0o600)
            guard lock >= 0 else { return }
            defer { flock(lock, LOCK_UN); close(lock) }
            // Bounded nonblocking lock wait prevents tracking failure delaying an agent.
            var acquired = false
            for _ in 0..<10 {
                if flock(lock, LOCK_EX | LOCK_NB) == 0 { acquired = true; break }
                usleep(10_000)
            }
            guard acquired else { return }
            var state: AgentSessionState?
            if let data = try? Data(contentsOf: url), data.count < 131_072,
               let previous = try? JSONDecoder().decode(AgentEvent.self, from: data) { state = .init(event: previous) }
            if state == nil {
                // Resuming an unobserved session is not evidence of current work.
                var initial = event
                if initial.lifecycle == .sessionResumed { initial.phase = .idle }
                state = .init(event: initial)
            } else { state?.apply(event) }
            if let state { try JSONEncoder().encode(state.event).write(to: url, options: .atomic) }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { /* Tracking is optional and must never block an agent operation. */ }
    }
}
