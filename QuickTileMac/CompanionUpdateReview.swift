import AppKit
import Combine
import QuickTileCore

/// Manual updates are reviewed before the user replaces an installed companion.
/// Downloaded code is never launched or copied over the running application here.
@MainActor final class CompanionUpdateReview: ObservableObject {
    @Published private(set) var checking = false
    @Published private(set) var message: String?
    func choose() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowedContentTypes = [.applicationBundle]
        panel.prompt = "Verify update"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.review(url)
        }
    }
    private func review(_ url: URL) {
        guard !checking else { return }
        checking = true; message = nil
        Task {
            defer { checking = false }
            do {
                guard let update = Bundle(url: url), update.bundleIdentifier == Bundle.main.bundleIdentifier else { throw QuickTileError.invalid("Choose a QuickTile companion update.") }
                let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
                let updateVersion = update.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
                let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
                let updateBuild = update.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
                guard updateVersion.compare(currentVersion, options: .numeric) == .orderedDescending ||
                      (updateVersion == currentVersion && updateBuild.compare(currentBuild, options: .numeric) == .orderedDescending) else { throw QuickTileError.invalid("Choose a newer version of the companion.") }
                let own = try await ProcessJob().run(executable: "/usr/bin/codesign", arguments: ["-dv", "--verbose=4", Bundle.main.bundlePath], timeout: 10)
                let team = own.error.split(separator: "\n").first { $0.hasPrefix("TeamIdentifier=") }.map { String($0.dropFirst("TeamIdentifier=".count)) }
                guard let team, team.count == 10, team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }), let identifier = Bundle.main.bundleIdentifier else { throw QuickTileError.unsupported("Update verification is available in a signed release build.") }
                let requirement = "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
                let signature = try await ProcessJob().run(executable: "/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", "--test-requirement", requirement, url.path], timeout: 20)
                guard signature.status == 0 else { throw QuickTileError.invalid("This update does not have the expected Developer ID signature.") }
                let gate = try await ProcessJob().run(executable: "/usr/sbin/spctl", arguments: ["--assess", "--type", "execute", url.path], timeout: 30)
                guard gate.status == 0 else { throw QuickTileError.invalid("Gatekeeper did not accept this update. Use the project's notarized download.") }
                message = "Verified version \(updateVersion). Quit QuickTile, replace the installed app with this update, then open it again."
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch { message = error.localizedDescription }
        }
    }
}
