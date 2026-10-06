import Foundation

public struct PresetBoardPage: Identifiable, Equatable, Sendable {
    public let name: String
    public let actionIDs: [String]
    public var id: String { name }
    public init(name: String, actionIDs: [String]) { self.name = name; self.actionIDs = actionIDs }
}
public struct PresetBoard: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let symbol: String
    public let profileID: String?
    public let pages: [PresetBoardPage]
    public let version: Int
    public var prerequisites: String {
        if let profileID, let profile = AppProfiles.profile(id: profileID) { return "Requires \(profile.title) and Accessibility. Default mappings need testing in your app and keymap." }
        return id == "agents" ? "Set up local coding-agent tracking on your Mac." : "Connect to your Mac. Some controls require Accessibility or supported hardware."
    }
    public func makePage(apps: [AppEntry] = [], preferredBundleID: String? = nil) -> DeckPage {
        var result = DeckPage(name: title, symbol: symbol)
        var order: [UUID?] = []
        for page in pages {
            var count = 0
            for id in page.actionIDs.prefix(8) {
                guard let item = ActionLibrary.actions.first(where: { $0.id == id }) else { order.append(nil); count += 1; continue }
                var tile = Tile(name: item.title, symbol: item.symbol, action: item.action)
                tile.presetID = item.id; tile.mappingVersion = version
                if let bundle = item.preset?.bundleID {
                    tile.targetBundleID = AppProfiles.resolve(bundleID: bundle, apps: apps, preferredBundleID: preferredBundleID)?.id
                }
                result.tiles.append(tile); order.append(tile.id); count += 1
            }
            order.append(contentsOf: repeatElement(nil, count: 8 - count))
        }
        result.tileOrder = order; result.sourcePresetID = id; result.linkedAppProfileID = profileID
        result.automaticSwitch = false; result.pageNames = pages.map(\.name)
        return result
    }
}
public enum PresetBoards {
    public static let boards: [PresetBoard] = {
        func page(_ profile: String, _ name: String, _ ids: [String]) -> PresetBoardPage { .init(name: name, actionIDs: ids.map { profile + "." + $0 }) }
        func board(_ profile: String, _ title: String, _ symbol: String, _ pages: [(String, [String])], profileID: String? = nil) -> PresetBoard {
            .init(id: profile, title: title, symbol: symbol, profileID: profileID ?? profile, pages: pages.map { page(profile, $0.0, $0.1) }, version: 1)
        }
        return [
            board("finalcut", "Final Cut Pro", "film", [("Cut", ["selection-tool","blade-tool","range-tool","trim-tool","append","insert","connect","overwrite"]), ("Review", ["play","frame-back","frame-forward","previous-edit","next-edit","marker","snapping","fit"]), ("Finish", ["undo","redo","transition","retime","disable","inspector","import","export"])]),
            board("resolve", "DaVinci Resolve", "circle.lefthalf.filled", [("Edit", ["selection-tool","trim-tool","blade-tool","insert","overwrite","replace","append","ripple"]), ("Review", ["play","frame-back","frame-forward","previous-edit","next-edit","marker","match","fit"]), ("Workspace", ["edit-page","fusion-page","color-page","fairlight-page","deliver-page","viewer","link-clips","transition"])]),
            board("premiere", "Premiere Pro", "film.stack", [("Cut", ["selection-tool","blade-tool","ripple-tool","rolling-tool","slip-tool","slide-tool","insert","overwrite"]), ("Review", ["play","frame-back","frame-forward","previous-edit","next-edit","marker","match","timeline"]), ("Finish", ["undo","redo","ripple","link-clips","speed","transition","import","export"])]),
            board("aftereffects", "After Effects", "diamond", [("Animate", ["position","scale","rotation","opacity","anchor","keyframes","easy-ease","graph"]), ("Layers", ["duplicate","precompose","split","trim-in","trim-out","lock","unlock","time-remap"]), ("Preview / export", ["play","frame-back","frame-forward","in","out","new-comp","comp-settings","render"])]),
            board("motion", "Apple Motion", "waveform.path", [("Animate", ["record","next-keyframe","previous-keyframe","ten-back","ten-forward","loop","range-start","range-end"]), ("Objects", ["new-group","camera","light","duplicate","group","ungroup","lock","solo"]), ("Preview", ["play","frame-back","frame-forward","preview-range","reset-range","inspector","undo","redo"])]),
            board("photoshop", "Photoshop", "paintbrush.pointed", [("Retouch", ["move-tool","selection-tool","brush-tool","erase-tool","clone-tool","heal-tool","brush-smaller","brush-larger"]), ("Layers", ["new-layer","duplicate","group","ungroup","merge-down","clipping","transform","deselect"]), ("Document", ["undo","redo","save","export","zoom-in","zoom-out","fit","fullscreen"])]),
            board("pixelmator", "Pixelmator Pro", "paintbrush", [("Retouch", ["move-tool","selection-tool","brush-tool","erase-tool","clone-tool","repair-tool","brush-smaller","brush-larger"]), ("Layers", ["new-layer","duplicate","group","ungroup","merge-selected","replace-layer","adjustments","select-layers"]), ("Document", ["undo","redo","save","export","zoom-in","zoom-out","fit","actual-size"])]),
            board("affinity-photo", "Affinity Photo", "photo", [("Retouch", ["move-tool","selection-tool","brush-tool","erase-tool","clone-tool","retouch-tool","brush-smaller","brush-larger"]), ("Layers", ["new-layer","duplicate","group","ungroup","merge-down","lock","deselect","invert-selection"]), ("Document", ["undo","redo","save","export","zoom-in","zoom-out","fit","fullscreen"])], profileID: "affinityphoto"),
            board("affinity-designer", "Affinity Designer", "pencil.tip", [("Draw", ["move-tool","node-tool","pen-tool","pencil-tool","shape-tool","fill-tool","text-tool","snapping"]), ("Arrange", ["duplicate","group","ungroup","bring-forward","send-backward","bring-front","send-back","lock"]), ("Document", ["undo","redo","save","export","zoom-in","zoom-out","fit","fullscreen"])], profileID: "affinitydesigner"),
            board("xcode", "Xcode", "hammer", [("Build / test", ["build","run","test","stop","next-error","previous-error","project","open-quickly"]), ("Debug", ["debug","breakpoint","continue","step-over","step-into","step-out","navigator","editor"]), ("Navigate", ["definition","comment","open-quickly","navigator","editor","project","next-error","previous-error"])]),
            board("vscode", "VS Code", "chevron.left.forwardslash.chevron.right", [("Develop", ["build","terminal","format","comment","project","run","recent","editor"]), ("Debug", ["debug","stop","continue","step-over","step-into","step-out","breakpoint","navigator"]), ("Navigate", ["definition","references","next-error","previous-error","recent","editor","navigator","git-status"])]),
            .init(id: "agents", title: "Coding agents", symbol: "terminal", profileID: nil, pages: [.init(name: "Agents", actionIDs: ["agent.codex","agent.claude","terminal","timer","editing.save","editing.find","editing.undo","editing.redo"]), .init(name: "Focus", actionIDs: ["timer","dial.volume","dial.brightness","media.playPause","media.previous","media.next","system.lock","system.showDesktop"])], version: 1),
            .init(id: "everyday", title: "Everyday work", symbol: "cursorarrow", profileID: nil, pages: [.init(name: "Essentials", actionIDs: ["editing.save","editing.find","editing.undo","editing.redo","editing.copy","editing.paste","system.showDesktop","system.lock"]), .init(name: "Focus", actionIDs: ["timer","dial.volume","dial.brightness","media.playPause","media.previous","media.next","system.screenshotArea","system.darkMode"])], version: 1)
        ]
    }()
    public static func board(id: String) -> PresetBoard? { boards.first { $0.id == id } }
}
