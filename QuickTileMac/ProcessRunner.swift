import Foundation
import QuickTileCore

/// Only callers with fixed executable paths and structured argument arrays can start jobs.
@MainActor final class ProcessJob {
    struct Output { let status: Int32; let text: String; let error: String }
    private let process = Process()
    private var continuation: CheckedContinuation<Output, Error>?
    private var monitor: Task<Void, Never>?
    private var directory: URL?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?
    private var finished = false

    func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> Output {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                do {
                    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("QuickTile-" + UUID().uuidString)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    directory = dir
                    let out = dir.appendingPathComponent("stdout"), err = dir.appendingPathComponent("stderr")
                    FileManager.default.createFile(atPath: out.path, contents: nil, attributes: [.posixPermissions: 0o600])
                    FileManager.default.createFile(atPath: err.path, contents: nil, attributes: [.posixPermissions: 0o600])
                    outputHandle = try FileHandle(forWritingTo: out); errorHandle = try FileHandle(forWritingTo: err)
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    process.standardOutput = outputHandle; process.standardError = errorHandle
                    process.standardInput = FileHandle.nullDevice
                    process.terminationHandler = { [weak self] _ in Task { @MainActor in self?.finish() } }
                    try process.run()
                    monitor = Task { [weak self] in
                        let deadline = Date().addingTimeInterval(timeout)
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .milliseconds(250))
                            guard !Task.isCancelled, let self, !self.finished else { return }
                            if Date() > deadline { self.cancel(QuickTileError.timeout); return }
                            for url in [out, err] {
                                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1_048_576 {
                                    self.cancel(QuickTileError.failed("The process produced too much output.")); return
                                }
                            }
                        }
                    }
                } catch { finish(error) }
            }
        } onCancel: { Task { @MainActor in self.cancel(CancellationError()) } }
    }
    private func cancel(_ error: Error) {
        if process.isRunning { process.terminate() }
        finish(error)
    }
    private func finish(_ error: Error? = nil) {
        guard !finished else { return }; finished = true
        monitor?.cancel(); monitor = nil
        process.terminationHandler = nil
        try? outputHandle?.close(); try? errorHandle?.close()
        let read: (String) -> String = { file in
            guard let dir = self.directory, let handle = try? FileHandle(forReadingFrom: dir.appendingPathComponent(file)) else { return "" }
            defer { try? handle.close() }
            return String(data: (try? handle.read(upToCount: 1_048_576)) ?? Data(), encoding: .utf8) ?? ""
        }
        let output = Output(status: process.isRunning ? -1 : process.terminationStatus, text: read("stdout"), error: read("stderr"))
        if let directory { try? FileManager.default.removeItem(at: directory) }
        let completion = continuation; continuation = nil
        if let error { completion?.resume(throwing: error) } else { completion?.resume(returning: output) }
    }
}
