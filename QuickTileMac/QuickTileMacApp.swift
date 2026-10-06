import SwiftUI
import QuickTileCore
import ServiceManagement
import ApplicationServices
import CoreImage.CIFilterBuiltins
import Darwin

@main
struct QuickTileMacApp: App {
    @StateObject private var server = MacServer()
    init() { if AgentStatusStore.handleCommandLine() { Darwin.exit(0) } }
    var body: some Scene {
        // The first scene is presented on launch. Keep the companion window
        // ahead of MenuBarExtra so a normal launch has visible controls.
        Window("QuickTile Mac", id: "companion") {
            CompanionPanel(server: server)
                .padding(12)
                .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .defaultPosition(.center)
        .defaultSize(width: 384, height: 600)
        .windowResizability(.contentSize)
        Window("QuickTile Settings", id: "settings") { CompanionSettings(server: server) }
            .defaultSize(width: 460, height: 580)
        MenuBarExtra("QuickTile", image: "MenuBarMark") {
            CompanionMenu(server: server)
        }.menuBarExtraStyle(.menu)
    }
}
struct CompanionMenu: View {
    @ObservedObject var server: MacServer
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(server.status)
        Divider()
        Button("Open Companion…", action: showCompanion)
        Button("Settings…") { openWindow(id: "settings"); NSApplication.shared.activate(ignoringOtherApps: true) }
        Button("Pair an iPhone…") {
            if server.invite == nil { server.createInvite() }
            showCompanion()
        }.disabled(server.paused)
        if !server.pending.isEmpty {
            Button("Review pairing request…", action: showCompanion)
        }
        Divider()
        Button(server.paused ? "Resume Connections" : "Pause Connections") { server.togglePaused() }
        Button(server.refreshing ? "Refreshing Apps…" : "Refresh Apps & Shortcuts") {
            Task { await server.refresh() }
        }.disabled(server.refreshing)
        Divider()
        Button("Quit QuickTile") {
            server.shutdown()
            NSApplication.shared.terminate(nil)
        }
    }

    private func showCompanion() {
        openWindow(id: "companion")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
struct CompanionPanel: View {
    @ObservedObject var server: MacServer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @State private var revoke: Credential?
    var body: some View {
        ZStack {
            if let request = server.pending.first {
                pairingConfirmation(request)
                    .id(request.id)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(1)
            } else {
                dashboard.transition(.opacity)
            }
        }
        .frame(width: 360, height: 576)
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.28), value: server.pending.first?.id)
        .onChange(of: server.pending.first?.id) { _, id in
            if id != nil {
                openWindow(id: "companion")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }
    private func pairingConfirmation(_ request: MacServer.PendingPair) -> some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.accentColor)
                .frame(width: 104, height: 104)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 28))
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Connect your iPhone?").font(.title2.weight(.semibold))
                Text(request.name).font(.headline).lineLimit(2)
                Text("Confirm this is your iPhone.")
                    .font(.callout).foregroundStyle(.secondary)
            }.multilineTextAlignment(.center)
            Text("It can open apps, send keys, run shortcuts, and control media on this Mac.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let error = server.error {
                Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Spacer()
            VStack(spacing: 10) {
                Button { server.approve(request) } label: {
                    Text("Connect").frame(maxWidth: .infinity).padding(.vertical, 7)
                }.buttonStyle(.borderedProminent).tint(.accentColor)
                    .accessibilityIdentifier("confirmConnection")
                Button("Cancel", role: .cancel) { server.deny(request) }
                    .buttonStyle(.plain).frame(height: 32).keyboardShortcut(.cancelAction)
            }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
    }
    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "square.grid.2x2.fill").font(.title2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("QuickTile").font(.headline)
                        Label(server.status, systemImage: server.paused ? "pause.circle" : (server.connectedNames.isEmpty ? "wifi" : "checkmark.shield")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { server.togglePaused() } label: { Image(systemName: server.paused ? "play.fill" : "pause.fill") }.help(server.paused ? "Resume connections" : "Pause all connections")
                }
                Divider()
                if let error = server.error {
                    Text(error).font(.callout).textSelection(.enabled)
                    Button("Dismiss message") { server.error = nil }
                }
                if let invite = server.invite {
                    VStack(spacing: 10) {
                        if let image = qr(invite) { Image(nsImage: image).interpolation(.none).resizable().frame(width: 300, height: 300).padding(16).background(.white).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityLabel("Pairing QR. Scan using QuickTile on your iPhone.") }
                        Text("Scan with QuickTile on your iPhone").font(.callout.weight(.medium))
                        Text("Expires \(invite.expiresAt, style: .relative). Keep this QR private.").font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("Pair without a camera") {
                            Text("Paste this full invitation on your iPhone. It contains a temporary secret; share it only with your own device.").font(.caption)
                            if let text = try? invite.encoded() { Text(text).font(.system(size: 10, design: .monospaced)).textSelection(.enabled) }
                        }
                        Button("Cancel pairing") { server.cancelInvite() }
                    }.frame(maxWidth: .infinity)
                } else {
                    Button { server.createInvite() } label: { Label("Pair an iPhone", systemImage: "qrcode").frame(maxWidth: .infinity).padding(.vertical, 6) }
                        .disabled(server.paused)
                }
                if !server.devices.isEmpty {
                    Text("PAIRED DEVICES").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(server.devices) { device in
                        HStack {
                            Image(systemName: "iphone")
                            VStack(alignment: .leading) { Text(device.name); Text("Paired \(device.createdAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Revoke") { revoke = device }.font(.caption)
                        }
                    }
                }
                Divider()
                Button("Settings…") { openWindow(id: "settings") }
                DisclosureGroup("Connection help") {
                    Text("Keep both devices on the same network and allow Local Network access. Keep the companion running and your Mac awake.\n\nMedia and keyboard controls require Accessibility. Media tiles send the Mac’s system playback keys to the active player, including Safari, YouTube, Spotify, and other apps.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
                HStack { Spacer(); Button("Quit") { server.shutdown(); NSApplication.shared.terminate(nil) } }
            }.padding(20)
        }
        .frame(width: 360).frame(maxHeight: 780)
        .tint(.primary)
        .alert("Remove this iPhone?", isPresented: Binding(get: { revoke != nil }, set: { if !$0 { revoke = nil } }), presenting: revoke) { device in
            Button("Cancel", role: .cancel) { revoke = nil }
            Button("Remove", role: .destructive) { server.revoke(device); revoke = nil }
        } message: { device in Text("\(device.name) will disconnect and need to pair again.") }
    }
    private func qr(_ invite: PairingInvite) -> NSImage? {
        guard let text = try? invite.encoded() else { return nil }
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(text.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage, let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

private struct AgentStatusSection: View {
    @ObservedObject var store: AgentStatusStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Agent status", systemImage: "waveform.path.ecg")
                Spacer()
                if store.enabled { Text("On").font(.caption).foregroundStyle(.secondary) }
                else { Button("Enable") { _ = store.enable() }.buttonStyle(.borderedProminent).controlSize(.small) }
            }
            if store.enabled {
                ForEach(store.snapshots, id: \.provider) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.provider.symbol).frame(width: 18)
                        Text(item.provider.title)
                        Spacer()
                        Text(item.phase.label).font(.caption).foregroundStyle(item.phase == .waiting ? .orange : .secondary)
                    }
                    if let health = item.health { Text(health.label).font(.caption).foregroundStyle(.secondary) }
                }
                if let issue = store.trackingIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
                if store.snapshots.contains(where: { $0.phase == .unknown }) {
                    Text("No activity received yet. Start a new agent session after setup.").font(.caption).foregroundStyle(.secondary)
                    Button("Repair tracking") { _ = store.enable() }.controlSize(.small)
                }
                Text("Codex: review and trust QuickTile hooks in /hooks, then start a coding turn. Editing hooks.json alone does not enable trusted hooks.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Tracks supported local coding sessions. Ordinary ChatGPT/Claude conversations and cloud agents are not tracked.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Codex hook setup", destination: URL(string: "https://learn.chatgpt.com/docs/hooks")!)
                Text(store.repliesConnected ? "Phone replies connected" : "Phone replies need a Codex control connection. Existing desktop sessions may support status tracking only.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Phone reply setup", destination: URL(string:"https://learn.chatgpt.com/docs/app-server")!).font(.caption)
                Button("Disable tracking", role: .destructive) { _ = store.disable() }.controlSize(.small)
                if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
            } else {
                Text("Show whether local Codex and Claude Code agents are running or waiting for input.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .padding(.top, 6)
    }
}
private struct CompanionSettings: View {
    @ObservedObject var server: MacServer
    @StateObject private var updateReview = CompanionUpdateReview()
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var accessibility = AXIsProcessTrusted()
    @State private var preferences: [String: String] = UserDefaults.standard.dictionary(forKey: "preferredAppProfiles") as? [String: String] ?? [:]
    var body: some View {
        Form {
            Section("Permissions") {
                Label(accessibility ? "Accessibility allowed" : "Accessibility needed for keys and media", systemImage: "keyboard")
                Button("Open Privacy & Security") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!) }
                Button("Refresh permission status") { accessibility = AXIsProcessTrusted(); Task { await server.refresh() } }
                Text("Other permissions are requested when a control needs them.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Applications") {
                Button(server.refreshing ? "Refreshing…" : "Refresh apps and shortcuts") { Task { await server.refresh() } }.disabled(server.refreshing)
                Button("Add an app from another folder…") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowedContentTypes = [.applicationBundle]
                    panel.begin { response in
                        guard response == .OK, let url = panel.url else { return }
                        do { try server.catalog.addApplication(url); Task { await server.refresh() } } catch { server.error = error.localizedDescription }
                    }
                }
                ForEach(AppProfiles.profiles.filter { AppProfiles.candidates(profileID: $0.id, apps: server.catalog.apps).count > 1 }) { profile in
                    Picker(profile.title, selection: Binding(get: { preferences[profile.id] ?? "" }, set: { value in
                        preferences[profile.id] = value.isEmpty ? nil : value
                        server.executor.preferredBundleIDs = preferences
                    })) {
                        Text("Automatic").tag("")
                        ForEach(AppProfiles.candidates(profileID: profile.id, apps: server.catalog.apps)) { app in Text(app.name).tag(app.id) }
                    }
                }
                if let note = server.catalog.note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Assistant") { GroqAssistantSettings(store: server.assistant) }
            Section("Coding agents") { AgentStatusSection(store: server.agentStatus) }
            Section("Companion") {
                Toggle("Launch at login", isOn: $login).onChange(of: login) { _, enabled in
                    do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { server.error = error.localizedDescription; login = SMAppService.mainApp.status == .enabled }
                }
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")").font(.caption).foregroundStyle(.secondary)
                Button(updateReview.checking ? "Verifying update…" : "Verify signed update…") { updateReview.choose() }.disabled(updateReview.checking)
                if let message = updateReview.message { Text(message).font(.caption).textSelection(.enabled) }
                Text("Install updates from the project's signed companion download. Quit QuickTile before replacing it; keep the same signing identity to preserve permissions.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = server.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }.formStyle(.grouped).padding(12)
    }
}
