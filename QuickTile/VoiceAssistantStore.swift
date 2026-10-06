import SwiftUI
import Combine
import Speech
import AVFoundation
import QuickTileCore

/// Audio and speech recognition stay on this device. Only a finished transcript leaves it.
@MainActor final class VoiceAssistantStore: ObservableObject {
    enum Phase: Equatable { case idle, requesting, listening, finishing, working }
    @Published private(set) var phase = Phase.idle
    @Published private(set) var tileID: UUID?
    @Published private(set) var level: Double = 0
    @Published private(set) var issue: String?
    @Published private(set) var message: String?
    var submit: ((UUID, String, @escaping (String, Bool) -> Void) -> Void)?
    var cancelRequest: ((UUID) -> Void)?
    var feedback: ((PhoneModel.Feedback) -> Void)?
    private var engine: AVAudioEngine?
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var deadline: Task<Void, Never>?
    private var latest = ""
    private var generation = UUID()
    private var lastLevel = Date.distantPast
    private var tapInstalled = false
    private var observer: NSObjectProtocol?
    init() {
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cancel() }
        }
    }
    #if DEBUG
    /// Deterministic UI presentation only; never starts audio, contacts Groq, or controls a Mac.
    func toggleFixture(_ id: UUID) {
        if phase == .idle { tileID = id; phase = .listening; level = 0.6 }
        else if phase == .listening { phase = .working; level = 0 }
        else { cancel() }
    }
    #endif
    func toggle(_ id: UUID) {
        if tileID == id, phase == .listening { finish(); return }
        if tileID == id, phase == .working { cancel(); return }
        guard phase == .idle else { return }
        generation = UUID(); let token = generation
        tileID = id; message = nil; issue = nil; phase = .requesting; latest = ""
        Task { [weak self] in
            guard let self else { return }
            let microphone = await AVAudioApplication.requestRecordPermission()
            let speech = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
            guard self.generation == token else { return }
            guard microphone, speech == .authorized else { self.fail("Allow Microphone and Speech Recognition in Settings."); return }
            guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
                self.fail("On-device speech isn’t available for this language. Choose a supported Siri language on your iPhone."); return
            }
            do { try self.start(recognizer, token: token) } catch { self.fail("Could not start the microphone. Try again.") }
        }
    }
    private func start(_ recognizer: SFSpeechRecognizer, token: UUID) throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audio.setActive(true)
        let engine = AVAudioEngine(), request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
        self.engine = engine; self.request = request
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal == true, failed = error != nil
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if let text { self.latest = String(text.prefix(2000)) }
                if self.phase == .finishing, final || failed { self.sendTranscript() }
                else if self.phase == .listening, final { self.finish() }
                else if self.phase == .listening, failed { self.fail("Speech recognition stopped. Try again.") }
            }
        }
        let input = engine.inputNode, format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw QuickTileError.failed("Microphone unavailable") }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let count = Int(buffer.frameLength)
            var sum: Double = 0
            for i in 0..<count { let value = Double(samples[i]); sum += value * value }
            let amplitude = min(1, max(0, (20 * log10(max(0.0001, sqrt(sum / Double(count)))) + 55) / 45))
            Task { @MainActor in
                guard let self, self.generation == token, self.phase == .listening, Date().timeIntervalSince(self.lastLevel) >= 0.03 else { return }
                self.lastLevel = Date(); self.level = self.level * 0.35 + amplitude * 0.65
            }
        }
        tapInstalled = true; engine.prepare(); try engine.start(); phase = .listening; feedback?(.soft)
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, self?.generation == token else { return }
            self?.finish()
        }
    }
    private func finish() {
        guard phase == .listening else { return }
        phase = .finishing; feedback?(.rigid); deadline?.cancel(); stopAudio(); request?.endAudio()
        let token = generation
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, self?.generation == token, self?.phase == .finishing else { return }
            self?.sendTranscript()
        }
    }
    private func sendTranscript() {
        guard phase == .finishing, let id = tileID else { return }
        deadline?.cancel(); deadline = nil; recognition?.cancel(); recognition = nil; request = nil
        let text = latest.trimmingCharacters(in: .whitespacesAndNewlines); latest = ""
        guard !text.isEmpty else { fail("No speech heard. Tap and try again."); return }
        phase = .working; let token = generation
        submit?(id, text) { [weak self] message, success in
            guard let self, self.generation == token else { return }
            self.phase = .idle; self.tileID = nil
            if success { self.message = message } else { self.issue = message }
            self.feedback?(success ? .success : .error)
        }
    }
    func cancel() {
        let running = phase == .working ? tileID : nil
        generation = UUID(); deadline?.cancel(); deadline = nil
        stopAudio(); request?.endAudio(); recognition?.cancel(); recognition = nil; request = nil
        latest = ""; phase = .idle; tileID = nil; message = nil; issue = nil
        if let running { cancelRequest?(running) }
    }
    private func fail(_ text: String) { cancel(); issue = text; feedback?(.error) }
    private func stopAudio() {
        engine?.stop()
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine = nil; level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct AssistantTileView: View {
    let id: UUID
    @ObservedObject var store: VoiceAssistantStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let activate: () -> Void
    private var active: Bool { store.tileID == id }
    var body: some View {
        Button(action: activate) {
            ZStack {
                if active && store.phase == .listening {
                    TimelineView(.animation(paused: reduceMotion)) { timeline in
                        Canvas { context, size in
                            var path = Path()
                            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 5
                            let amplitude = 3 + store.level * size.height * 0.36
                            for step in 0...100 {
                                let x = Double(step) / 100
                                let y = size.height / 2 + sin(x * .pi * 6 - time) * amplitude * sin(x * .pi)
                                let point = CGPoint(x: x * size.width, y: y)
                                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                            }
                            context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        }
                    }.frame(maxWidth: 150).frame(height: 70).padding(.horizontal, 24)
                } else if active && store.phase != .idle { ProgressView().controlSize(.large) }
                else { Image(systemName: "waveform").font(.system(size: 40, weight: .regular)) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .background(TileMetrics.surface, in: RoundedRectangle(cornerRadius: TileMetrics.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: TileMetrics.cornerRadius).strokeBorder(active && store.phase == .listening ? Color.primary.opacity(0.35) : .clear, lineWidth: 1))
            .accessibilityLabel(active ? store.phase == .listening ? "Stop recording and send command" : "Cancel assistant request" : "Assistant. Record a voice command")
            .accessibilityIdentifier("assistantTile")
    }
}
