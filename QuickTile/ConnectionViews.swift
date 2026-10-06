import SwiftUI
import UIKit
import AVFoundation
import QuickTileCore

struct MacPickerView: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var invitation = ""
    @State private var forget: Credential?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(model.state == .connected ? model.state.label : (model.pairingStage?.label ?? model.state.label), systemImage: model.state == .connected ? "checkmark.shield" : "wifi")
                    if model.state == .connecting || model.state == .awaitingApproval {
                        ProgressView()
                            .tint(.accentColor)
                        Text(model.state == .awaitingApproval ? "Approve this iPhone on the Mac." : "Connecting to the Mac…")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(.red)
                    }
                    if model.state == .awaitingApproval {
                        Button("Cancel pairing") { model.cancelPairing() }
                    }
                }
                if !model.credentials.isEmpty {
                    Section("Your Macs") {
                        ForEach(model.credentials) { credential in
                            HStack {
                                Button { model.select(credential); dismiss() } label: {
                                    Label(credential.name, systemImage: model.selected?.macID == credential.macID ? "checkmark.circle" : "desktopcomputer")
                                }.buttonStyle(.plain)
                                Spacer()
                                Button { forget = credential } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }.accessibilityLabel("Forget \(credential.name)")
                            }
                        }
                    }
                }
                Section("Nearby companions") {
                    if model.nearby.isEmpty {
                        Text("Looking for QuickTile on your local network…").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.nearby) { mac in
                            Label(mac.name, systemImage: "desktopcomputer")
                        }
                    }
                    Text("Open QuickTile on your Mac, choose Pair an iPhone, then scan its QR.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.scanning = true } } label: { Label("Scan pairing QR", systemImage: "qrcode.viewfinder") }
                    DisclosureGroup("Paste a full pairing invitation") {
                        TextField("quicktile://pair/…", text: $invitation, axis: .vertical).font(.caption.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                        Button("Pair") { model.pair(invitation); invitation = "" }.disabled(invitation.isEmpty)
                    }
                } footer: { Text("Keep your pairing invitation private. Confirm the connection on your Mac.") }
                Section("Troubleshooting") {
                    Text("Your iPhone must use Wi-Fi. Your Mac can use Wi-Fi or Ethernet on the same reachable LAN. Guest networks, VPNs, firewalls, or client isolation can prevent discovery.")
                    Button("Retry discovery") { model.retry() }
                    Button("Open QuickTile settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                    Text("If access was denied, allow QuickTile under Settings → Privacy & Security → Local Network.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Your Mac").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Forget \(forget?.name ?? "Mac")?", isPresented: Binding(get: { forget != nil }, set: { if !$0 { forget = nil } })) {
                Button("Forget Mac", role: .destructive) { if let forget { model.forget(forget) }; forget = nil }
            } message: { Text("The saved credential is removed from this iPhone. Your layout stays on this device. Revoke the phone on the Mac to remove its authorization there too.") }
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                if model.layout != nil {
                    Section("Appearance") {
                        Picker("Theme", selection: setting(\.theme, fallback: .system)) { ForEach(Theme.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.accessibilityIdentifier("themePicker")
                        Toggle("Haptics", isOn: setting(\.haptics, fallback: true))
                    }
                    Section {
                        Toggle("Keep screen awake", isOn: setting(\.keepAwake, fallback: false))
                    } footer: { Text("Only while QuickTile is in the foreground and connected to this Mac.") }
                }
                if model.layout != nil {
                    Section { Toggle("Completion notifications", isOn: Binding(get: { model.layout?.settings.timerNotifications == true }, set: { model.layout?.settings.timerNotifications = $0 })) } header: { Text("Timers") } footer: { Text("Haptic reminders play while QuickTile is open. Notifications can alert you when it is in the background.") }
                }
                if model.previewMode { Section { Text("Preview board. Controls do not send commands to a Mac."); Button("Leave preview") { model.leavePreview(); dismiss() } } }
                Section("Mac capabilities") {
                    if model.state == .connected {
                        Label(model.capabilities.keyboard ? "Keyboard access allowed" : "Keyboard access needs Mac approval", systemImage: "keyboard")
                        Label(model.capabilities.mediaKeys == true ? "Media controls ready" : "Media controls need Accessibility", systemImage: "playpause")
                        Label(model.capabilities.volume ? "Output volume supported" : "Output uses hardware volume controls", systemImage: "speaker.wave.2")
                        Button("Refresh catalog") { model.refreshCatalog() }
                    } else { Text("Connect to your Mac to see available controls.").foregroundStyle(.secondary) }
                    Text("Media keys control the current player. Allow Accessibility on your Mac to use media and keyboard controls.").font(.caption).foregroundStyle(.secondary)
                }
                Section("QuickTile") {
                    NavigationLink("Privacy policy") { PrivacyPolicyView() }.accessibilityIdentifier("privacyPolicy")
                    if let url = URL(string: Bundle.main.object(forInfoDictionaryKey: "QuickTileSupportURL") as? String ?? ""), url.scheme == "https" {
                        Link("Support", destination: url)
                    }
                    Text("Free and open source. No QuickTile account, ads, or subscription. Optional Groq usage uses your own account.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func setting<T>(_ key: WritableKeyPath<DeckSettings, T>, fallback: T) -> Binding<T> {
        Binding(get: { model.layout?.settings[keyPath: key] ?? fallback }, set: { model.layout?.settings[keyPath: key] = $0; model.feedback(.selection) })
    }
}
private struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section { Text("QuickTile has no QuickTile account, advertising, or analytics upload. Mac control uses your local network. The optional voice assistant uses your Groq account.") } footer: { Text("Updated October 5, 2026") }
            Section("On your devices") {
                Text("Pairing credentials are stored in Keychain. Boards, preferences, icons, app catalogs, and timers are stored locally. Your iPhone and paired Mac exchange action requests and control state over an encrypted local connection.")
                Text("Agent tracking is optional. It uses local lifecycle events and, for Codex compatibility, local session records. Opening a waiting tile shares its pending question or approval details with your paired iPhone. Answers use the local connection and are never sent to Groq. Full conversations and agent output stay on your Mac.")
            }
            Section("Voice assistant") {
                Text("Audio stays on your iPhone. After you agree to use the assistant, your finished transcript and available Mac app, Shortcut, and supported action names are sent to Groq for interpretation. Groq receives normal request metadata and uses its own data policy and account settings.")
                Text("The API key stays in your Mac’s Keychain and is excluded from board exports. QuickTile does not save recordings or a transcript history. Remove the key in Mac Settings to disable the assistant.")
                Link("Groq data policy", destination: URL(string: "https://console.groq.com/docs/your-data")!)
            }
            Section("Website icons") {
                Text("Website icons are requested directly from the site's origin and its declared icon hosts using HTTPS, without cookies. Those servers may receive your IP address. Choose a symbol or custom image to avoid icon requests for that tile.")
            }
            Section("Permissions") {
                Text("Local Network enables pairing and control. The camera scans pairing codes. Optional notifications alert you when timers finish. On Mac, keyboard and media keys need Accessibility; selected player and system actions may need Automation. Optional voice commands use Microphone and Speech Recognition for on-device transcription. QuickTile does not request screen recording access.")
            }
            Section("Sharing and removal") {
                Text("Board exports include names, mappings, website addresses, and selected icons. They exclude pairing credentials and agent transcripts. Review them before sharing.")
                Text("Forget a Mac to remove its pairing credential. Delete boards or uninstall QuickTile to remove local layouts. Before removing the Mac companion, disable agent tracking and launch at login. Local backups may remain until their app data is removed.")
            }
            Section("Support") {
                Text("When you email support, we receive the address and details you choose to send. Send only the information needed to describe the issue.")
                Link("sahilambegaonkar@gmail.com", destination: URL(string: "mailto:sahilambegaonkar@gmail.com")!)
                if let url = URL(string: Bundle.main.object(forInfoDictionaryKey: "QuickTilePrivacyURL") as? String ?? ""), url.scheme == "https" { Link("View policy on the web", destination: url) }
            }
        }.navigationTitle("Privacy policy").navigationBarTitleDisplayMode(.inline)
    }
}
struct QRScannerView: View {
    var onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var permitted = false
    @State private var permissionDenied = false
    @State private var detail: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if permitted { CameraPreview(onScan: onScan, onError: { detail = $0 }).clipShape(RoundedRectangle(cornerRadius: 24)).frame(maxHeight: 430) }
                else { Image(systemName: "qrcode.viewfinder").font(.system(size: 70, weight: .ultraLight)).frame(height: 240) }
                Text("Scan your Mac’s pairing QR").font(.headline)
                Text(detail ?? "In the Mac menu bar, open QuickTile and choose Pair an iPhone. Then approve this phone on the Mac.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if permissionDenied { Button("Open Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) } }
                Spacer()
            }.padding(24).navigationTitle("Pair your Mac").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .task {
                    switch AVCaptureDevice.authorizationStatus(for: .video) {
                    case .authorized: permitted = true; permissionDenied = false
                    case .notDetermined:
                        permitted = await AVCaptureDevice.requestAccess(for: .video)
                        permissionDenied = AVCaptureDevice.authorizationStatus(for: .video) == .denied
                        if !permitted { detail = "Camera access is off. Enable it in Settings, or paste the full invitation in Your Mac." }
                    case .denied:
                        permissionDenied = true
                        detail = "Camera access is off. Enable it in Settings, or paste the full invitation in Your Mac."
                    case .restricted:
                        detail = "Camera access is restricted on this device. Paste the pairing invitation in Your Mac."
                    @unknown default:
                        detail = "Camera access is unavailable. Paste the pairing invitation in Your Mac."
                    }
                }
        }
    }
}
struct CameraPreview: UIViewRepresentable {
    let onScan: (String) -> Void
    let onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onError: onError) }
    func makeUIView(context: Context) -> CameraView {
        let view = CameraView(); context.coordinator.start(in: view); return view
    }
    func updateUIView(_ uiView: CameraView, context: Context) {}
    static func dismantleUIView(_ uiView: CameraView, coordinator: Coordinator) { coordinator.stop() }
    final class CameraView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = preview.connection {
                let orientation = window?.windowScene?.interfaceOrientation ?? .portrait
                let angle: CGFloat = orientation == .landscapeLeft ? 0 : orientation == .landscapeRight ? 180 : orientation == .portraitUpsideDown ? 270 : 90
                if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
            }
        }
    }
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let session = AVCaptureSession()
        let queue = DispatchQueue(label: "QuickTile.camera")
        let onScan: (String) -> Void
        let onError: (String) -> Void
        var scanned = false
        init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) { self.onScan = onScan; self.onError = onError }
        func start(in view: CameraView) {
            view.preview.session = session; view.preview.videoGravity = .resizeAspectFill
            queue.async { [self] in
                guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else {
                    DispatchQueue.main.async { self.onError("No camera is available. On a simulator, paste the full invitation in Your Mac.") }; return
                }
                session.beginConfiguration(); session.addInput(input)
                let output = AVCaptureMetadataOutput()
                guard session.canAddOutput(output) else { session.commitConfiguration(); return }
                session.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
                session.commitConfiguration(); session.startRunning()
            }
        }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !scanned, let text = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("quicktile://pair/") else {
                onError("That code is not a QuickTile pairing code."); return
            }
            scanned = true; onScan(text); stop()
        }
        func stop() { queue.async { [self] in if session.isRunning { session.stopRunning() } } }
    }
}
