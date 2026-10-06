import Foundation

public struct AppProfile: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let bundleIDs: [String]
    public let versionedPrefixes: [String]
    public let symbol: String
    public let shortcutDocumentation: String?
    public func matches(_ bundleID: String) -> Bool {
        bundleIDs.contains(where: { $0.caseInsensitiveCompare(bundleID) == .orderedSame })
        || versionedPrefixes.contains(where: { bundleID.lowercased().hasPrefix($0.lowercased() + ".") })
    }
}
public enum AppProfiles {
    public static let profiles: [AppProfile] = [
        .init(id: "finalcut", title: "Final Cut Pro", bundleIDs: ["com.apple.FinalCut", "com.apple.FinalCutApp"], versionedPrefixes: [], symbol: "film", shortcutDocumentation: "https://support.apple.com/guide/final-cut-pro/keyboard-shortcuts-ver90ba5929/mac"),
        .init(id: "resolve", title: "DaVinci Resolve", bundleIDs: ["com.blackmagic-design.DaVinciResolve", "com.blackmagic-design.DaVinciResolveStudio"], versionedPrefixes: [], symbol: "circle.lefthalf.filled", shortcutDocumentation: "https://www.blackmagicdesign.com/support/family/davinci-resolve-and-fusion"),
        .init(id: "premiere", title: "Premiere Pro", bundleIDs: ["com.adobe.PremierePro"], versionedPrefixes: ["com.adobe.PremierePro"], symbol: "film.stack", shortcutDocumentation: "https://helpx.adobe.com/premiere-pro/using/keyboard-shortcuts.html"),
        .init(id: "aftereffects", title: "After Effects", bundleIDs: ["com.adobe.AfterEffects"], versionedPrefixes: ["com.adobe.AfterEffects"], symbol: "diamond", shortcutDocumentation: "https://helpx.adobe.com/after-effects/using/keyboard-shortcuts-reference.html"),
        .init(id: "motion", title: "Apple Motion", bundleIDs: ["com.apple.Motion"], versionedPrefixes: [], symbol: "waveform.path", shortcutDocumentation: "https://support.apple.com/guide/motion/keyboard-shortcuts-motn3b65f6c0/mac"),
        .init(id: "photoshop", title: "Photoshop", bundleIDs: ["com.adobe.Photoshop"], versionedPrefixes: ["com.adobe.Photoshop"], symbol: "paintbrush.pointed", shortcutDocumentation: "https://helpx.adobe.com/photoshop/using/default-keyboard-shortcuts.html"),
        .init(id: "pixelmator", title: "Pixelmator Pro", bundleIDs: ["com.pixelmatorteam.pixelmator.x", "com.apple.PixelmatorPro"], versionedPrefixes: [], symbol: "paintbrush", shortcutDocumentation: "https://www.pixelmator.com/support/guide/pixelmator-pro/keyboard-shortcuts-7b83a09c/"),
        .init(id: "affinityphoto", title: "Affinity Photo", bundleIDs: ["com.seriflabs.affinityphoto", "com.seriflabs.affinityphoto2"], versionedPrefixes: [], symbol: "photo", shortcutDocumentation: "https://affinity.help/photo2/en-US.lproj/pages/Workspace/shortcuts.html"),
        .init(id: "affinitydesigner", title: "Affinity Designer", bundleIDs: ["com.seriflabs.affinitydesigner", "com.seriflabs.affinitydesigner2"], versionedPrefixes: [], symbol: "pencil.tip", shortcutDocumentation: "https://affinity.help/designer2/en-US.lproj/pages/Workspace/shortcuts.html"),
        .init(id: "xcode", title: "Xcode", bundleIDs: ["com.apple.dt.Xcode"], versionedPrefixes: [], symbol: "hammer", shortcutDocumentation: "https://developer.apple.com/documentation/xcode"),
        .init(id: "vscode", title: "VS Code", bundleIDs: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"], versionedPrefixes: [], symbol: "chevron.left.forwardslash.chevron.right", shortcutDocumentation: "https://code.visualstudio.com/docs/reference/default-keybindings"),
        .init(id: "codex", title: "Codex", bundleIDs: ["com.openai.codex"], versionedPrefixes: [], symbol: "terminal", shortcutDocumentation: nil),
        .init(id: "claude", title: "Claude", bundleIDs: ["com.anthropic.claudefordesktop"], versionedPrefixes: [], symbol: "sparkle", shortcutDocumentation: nil)
    ]
    public static func profile(id: String) -> AppProfile? { profiles.first { $0.id == id } }
    public static func profile(bundleID: String) -> AppProfile? { profiles.first { $0.matches(bundleID) } }
    public static func matches(profileID: String, bundleID: String) -> Bool { profile(id: profileID)?.matches(bundleID) == true }
    public static func candidates(profileID: String, apps: [AppEntry]) -> [AppEntry] {
        guard let profile = profile(id: profileID) else { return [] }
        return apps.filter { profile.matches($0.id) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public static func resolve(bundleID: String, apps: [AppEntry], preferredBundleID: String? = nil) -> AppEntry? {
        let profile = profile(bundleID: bundleID) ?? profile(id: bundleID)
        if let preferredBundleID, let preferred = apps.first(where: { $0.id == preferredBundleID }),
           profile?.matches(preferred.id) == true || preferred.id == bundleID { return preferred }
        if let exact = apps.first(where: { $0.id == bundleID }) { return exact }
        guard let profile else { return nil }
        for alias in profile.bundleIDs {
            if let exact = apps.first(where: { $0.id == alias }) { return exact }
        }
        return candidates(profileID: profile.id, apps: apps).last
    }
}
