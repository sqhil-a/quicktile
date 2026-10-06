import Foundation

public enum ActionCategory: String, CaseIterable, Identifiable, Sendable {
    case apps = "Apps & links", media = "Media", mac = "Mac controls", video = "Video editing", photo = "Photo & design", development = "Development", editing = "Everyday", ai = "AI agents"
    public var id: String { rawValue }
    public var symbol: String {
        switch self { case .apps: "app"; case .media: "playpause"; case .mac: "desktopcomputer"; case .video: "film"; case .photo: "photo.artframe"; case .development: "chevron.left.forwardslash.chevron.right"; case .editing: "cursorarrow"; case .ai: "terminal" }
    }
}
public enum PresetStep: Equatable, Sendable { case key(KeyboardShortcut) }
public struct ActionPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let symbol: String
    public let category: ActionCategory
    public let appName: String
    public let bundleID: String
    public let steps: [PresetStep]
    public var shortcut: KeyboardShortcut? {
        guard steps.count == 1, case .key(var key) = steps[0] else { return nil }
        key.targetBundleID = bundleID; return key
    }
}
public struct LibraryAction: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let category: ActionCategory
    public let action: DeckAction
    public let symbol: String
    public init(id: String, title: String, detail: String, category: ActionCategory, action: DeckAction, symbol: String) {
        self.id = id; self.title = title; self.detail = detail; self.category = category; self.action = action; self.symbol = symbol
    }
    public var preset: ActionPreset? { if case .preset(let id) = action { ActionLibrary.preset(id: id) } else { nil } }
}
public enum ActionLibrary {
    public static func preset(id: String) -> ActionPreset? { byID[id] }
    private static let byID = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0) })
    public static let presets: [ActionPreset] = {
        var result: [ActionPreset] = []
        func key(_ profile: String, _ app: String, _ bundle: String, _ category: ActionCategory, _ id: String, _ title: String, _ symbol: String, _ key: String, _ modifiers: [KeyModifier] = []) {
            result.append(ActionPreset(id: profile + "." + id, title: title, symbol: symbol, category: category, appName: app, bundleID: bundle, steps: [.key(KeyboardShortcut(key: key, modifiers: modifiers))]))
        }
        for (profile, app, bundle) in [("finalcut", "Final Cut Pro", "com.apple.FinalCut"), ("premiere", "Premiere Pro", "com.adobe.PremierePro"), ("resolve", "DaVinci Resolve", "com.blackmagic-design.DaVinciResolve"), ("motion", "Apple Motion", "com.apple.Motion"), ("aftereffects", "After Effects", "com.adobe.AfterEffects")] {
            func add(_ id: String, _ title: String, _ symbol: String, _ value: String, _ modifiers: [KeyModifier] = []) { key(profile, app, bundle, .video, id, title, symbol, value, modifiers) }
            add("play", "Play / pause", "playpause.fill", "space")
            add("frame-back", "Previous frame", "backward.frame.fill", profile == "aftereffects" ? "pageup" : "left")
            add("frame-forward", "Next frame", "forward.frame.fill", profile == "aftereffects" ? "pagedown" : "right")
            add("start", "Timeline start", "backward.end.fill", "home")
            add("end", "Timeline end", "forward.end.fill", "end")
            add("in", profile == "aftereffects" ? "Work area start" : "Mark in", "arrow.right.to.line", profile == "aftereffects" ? "b" : "i")
            add("out", profile == "aftereffects" ? "Work area end" : "Mark out", "arrow.left.to.line", profile == "aftereffects" ? "n" : "o")
            if profile != "motion" { add("split", "Split clip", "scissors", profile == "premiere" ? "k" : profile == "aftereffects" ? "d" : "b", profile == "aftereffects" ? [.command, .shift] : [.command]) }
            if profile != "aftereffects" { add("marker", "Add marker", "bookmark.fill", "m") }
            add("undo", "Undo", "arrow.uturn.backward", "z", [.command])
            add("redo", "Redo", "arrow.uturn.forward", "z", [.command, .shift])
            add("select", "Select all clips", "checkmark.rectangle.stack", "a", [.command])
            add("deselect", "Deselect clips", "rectangle.dashed", "a", [.command, .shift])
            if profile != "aftereffects" { add("snapping", "Toggle snapping", "link", profile == "premiere" ? "s" : "n") }
            if profile != "aftereffects" && profile != "motion" {
            add("reverse", "Shuttle backward", "backward.fill", "j")
            add("stop", "Stop timeline", "stop.fill", "k")
            add("forward", "Shuttle forward", "forward.fill", "l")
            }
            if profile == "finalcut" {
                add("ripple", "Ripple delete", "delete.left.fill", "delete")
                add("viewer", "Fullscreen viewer", "arrow.up.left.and.arrow.down.right", "f", [.command, .shift])
                add("timeline", "Focus timeline", "film.stack", "2", [.command])
                add("zoom-in", "Zoom timeline in", "plus.magnifyingglass", "=", [.command])
                add("zoom-out", "Zoom timeline out", "minus.magnifyingglass", "-", [.command])
                add("export", "Export", "square.and.arrow.up", "e", [.command])
                add("nudge-left", "Nudge clip left", "arrow.left", ",")
                add("nudge-right", "Nudge clip right", "arrow.right", ".")
            } else if profile == "premiere" {
                add("ripple", "Ripple delete", "delete.left.fill", "forwarddelete", [.shift])
                add("viewer", "Fullscreen viewer", "arrow.up.left.and.arrow.down.right", "`", [.control])
                add("timeline", "Focus timeline", "film.stack", "3", [.shift])
                add("zoom-in", "Zoom timeline in", "plus.magnifyingglass", "=")
                add("zoom-out", "Zoom timeline out", "minus.magnifyingglass", "-")
                add("export", "Export", "square.and.arrow.up", "m", [.command])
                add("nudge-left", "Nudge clip left", "arrow.left", "left", [.command])
                add("nudge-right", "Nudge clip right", "arrow.right", "right", [.command])
            }
            if profile == "finalcut" {
                add("selection-tool", "Selection tool", "cursorarrow", "a")
                add("blade-tool", "Blade tool", "scissors", "b")
                add("range-tool", "Range selection", "rectangle.dashed", "r")
                add("trim-tool", "Trim tool", "arrow.left.and.right", "t")
                add("position-tool", "Position tool", "move.3d", "p")
                add("append", "Append clip", "plus.rectangle.on.rectangle", "e")
                add("insert", "Insert clip", "rectangle.stack.badge.plus", "w")
                add("connect", "Connect clip", "link", "q")
                add("overwrite", "Overwrite clip", "rectangle.on.rectangle", "d")
                add("transition", "Add default transition", "rectangle.split.2x1", "t", [.command])
                add("disable", "Enable / disable clip", "eye.slash", "v")
                add("retime", "Retime controls", "speedometer", "r", [.command])
                add("fit", "Fit timeline", "arrow.up.left.and.arrow.down.right", "z", [.shift])
                add("inspector", "Inspector", "slider.horizontal.3", "4", [.command])
                add("import", "Import media", "square.and.arrow.down", "i", [.command])
                add("detach-audio", "Detach audio", "waveform", "s", [.control, .shift])
                add("next-edit", "Next edit", "arrow.right.to.line", "down")
                add("previous-edit", "Previous edit", "arrow.left.to.line", "up")
            }
            if profile == "premiere" {
                add("selection-tool", "Selection tool", "cursorarrow", "v")
                add("blade-tool", "Razor tool", "scissors", "c")
                add("ripple-tool", "Ripple edit tool", "arrow.left.and.right", "b")
                add("rolling-tool", "Rolling edit tool", "arrow.left.arrow.right", "n")
                add("slip-tool", "Slip tool", "arrow.left.and.right.righttriangle.left.righttriangle.right", "y")
                add("slide-tool", "Slide tool", "rectangle.and.arrow.up.right.and.arrow.down.left", "u")
                add("pen-tool", "Pen tool", "pencil.tip", "p")
                add("hand-tool", "Hand tool", "hand.draw", "h")
                add("insert", "Insert clip", "rectangle.stack.badge.plus", ",")
                add("overwrite", "Overwrite clip", "rectangle.on.rectangle", ".")
                add("transition", "Video transition", "rectangle.split.2x1", "d", [.command])
                add("audio-transition", "Audio transition", "waveform", "d", [.command, .shift])
                add("speed", "Speed / duration", "speedometer", "r", [.command])
                add("group", "Group clips", "square.stack.3d.up", "g", [.command])
                add("ungroup", "Ungroup clips", "square.stack.3d.down.right", "g", [.command, .shift])
                add("link-clips", "Link / unlink clips", "link", "l", [.command])
                add("match", "Match frame", "viewfinder", "f")
                add("import", "Import media", "square.and.arrow.down", "i", [.command])
                add("next-edit", "Next edit", "arrow.right.to.line", "down")
                add("previous-edit", "Previous edit", "arrow.left.to.line", "up")
            }
            if profile == "resolve" {
                add("selection-tool", "Selection mode", "cursorarrow", "a")
                add("trim-tool", "Trim edit mode", "arrow.left.and.right", "t")
                add("blade-tool", "Blade mode", "scissors", "b")
                add("insert", "Insert clip", "rectangle.stack.badge.plus", "f9")
                add("overwrite", "Overwrite clip", "rectangle.on.rectangle", "f10")
                add("replace", "Replace clip", "arrow.triangle.2.circlepath", "f11")
                add("append", "Append to end", "plus.rectangle.on.rectangle", "f12", [.shift])
                add("ripple", "Ripple delete", "delete.left.fill", "forwarddelete", [.shift])
                add("transition", "Add transition", "rectangle.split.2x1", "t", [.command])
                add("disable", "Enable / disable clip", "eye.slash", "d")
                add("link-clips", "Link / unlink clips", "link", "l", [.command, .option])
                add("match", "Match frame", "viewfinder", "f")
                add("fit", "Fit timeline", "arrow.up.left.and.arrow.down.right", "z", [.shift])
                add("viewer", "Cinema viewer", "arrow.up.left.and.arrow.down.right", "f", [.command])
                add("edit-page", "Edit page", "film", "4", [.shift])
                add("fusion-page", "Fusion page", "sparkles", "5", [.shift])
                add("color-page", "Color page", "paintpalette", "6", [.shift])
                add("fairlight-page", "Fairlight page", "waveform", "7", [.shift])
                add("deliver-page", "Deliver page", "square.and.arrow.up", "8", [.shift])
                add("next-edit", "Next edit", "arrow.right.to.line", "down")
                add("previous-edit", "Previous edit", "arrow.left.to.line", "up")
            }
            if profile == "aftereffects" {
                add("position", "Position", "move.3d", "p")
                add("scale", "Scale", "arrow.up.left.and.arrow.down.right", "s")
                add("rotation", "Rotation", "rotate.right", "r")
                add("opacity", "Opacity", "circle.lefthalf.filled", "t")
                add("anchor", "Anchor point", "scope", "a")
                add("keyframes", "Animated properties", "diamond", "u")
                add("effects", "Layer effects", "sparkles", "e")
                add("masks", "Mask properties", "theatermasks", "m")
                add("duplicate", "Duplicate layer", "plus.square.on.square", "d", [.command])
                add("precompose", "Precompose", "square.stack.3d.up", "c", [.command, .shift])
                add("trim-in", "Trim layer start", "arrow.right.to.line", "[", [.option])
                add("trim-out", "Trim layer end", "arrow.left.to.line", "]", [.option])
                add("time-remap", "Time remapping", "clock.arrow.circlepath", "t", [.command, .option])
                add("reverse-layer", "Reverse layer", "backward.fill", "r", [.command, .option])
                add("lock", "Lock layer", "lock", "l", [.command])
                add("unlock", "Unlock all layers", "lock.open", "l", [.command, .shift])
                add("new-comp", "New composition", "film.badge.plus", "n", [.command])
                add("comp-settings", "Composition settings", "slider.horizontal.3", "k", [.command])
                add("new-solid", "New solid", "square.fill", "y", [.command])
                add("render", "Add to render queue", "square.and.arrow.up", "m", [.command])
                add("import", "Import media", "square.and.arrow.down", "i", [.command])
                add("easy-ease", "Easy ease", "waveform.path", "f9")
                add("graph", "Graph editor", "chart.xyaxis.line", "f3", [.shift])
                add("next-keyframe", "Next keyframe", "forward.end", "k")
                add("previous-keyframe", "Previous keyframe", "backward.end", "j")
            }
            if profile == "motion" {
                add("inspector", "Project properties", "slider.horizontal.3", "j", [.command])
                add("ripple", "Ripple delete", "delete.left.fill", "delete", [.shift])
                add("paste-special", "Paste special", "doc.on.clipboard", "v", [.command, .option])
                add("next-keyframe", "Next keyframe", "forward.end", "k", [.shift])
                add("previous-keyframe", "Previous keyframe", "backward.end", "k", [.option])
                add("reset-range", "Reset play range", "arrow.counterclockwise", "x", [.option])
                add("preview-range", "RAM preview range", "play.rectangle", "r", [.command])
                add("new-group", "New group", "square.stack.3d.up", "n", [.command, .shift])
                add("camera", "New camera", "camera", "c", [.command, .option])
                add("light", "New light", "lightbulb", "l", [.command, .shift])
                add("lock", "Lock / unlock object", "lock", "l", [.control])
                add("solo", "Solo object", "headphones", "s", [.control])
                add("record", "Record animation", "record.circle", "a")
                add("loop", "Loop playback", "repeat", "l", [.shift])
                add("range-start", "Go to range start", "backward.end", "home", [.shift])
                add("range-end", "Go to range end", "forward.end", "end", [.shift])
                add("ten-back", "Back ten frames", "backward.frame", "left", [.shift])
                add("ten-forward", "Forward ten frames", "forward.frame", "right", [.shift])
                add("duplicate", "Duplicate object", "plus.square.on.square", "d", [.command])
                add("group", "Group objects", "square.stack.3d.up", "g", [.command, .shift])
                add("ungroup", "Ungroup objects", "square.stack.3d.down.right", "g", [.command, .option])
                add("import", "Import media", "square.and.arrow.down", "i", [.command])
                add("new", "New project", "doc.badge.plus", "n", [.command])
                add("open", "Open project", "folder", "o", [.command])
                add("save-as", "Save as", "square.and.arrow.down.on.square", "s", [.command, .shift])
                add("close", "Close project", "xmark.square", "w", [.command])
            }
            add("copy", "Copy", "doc.on.doc", "c", [.command])
            add("cut", "Cut", "scissors", "x", [.command])
            add("paste", "Paste", "doc.on.clipboard", "v", [.command])
            add("save", "Save", "square.and.arrow.down", "s", [.command])
        }
        for (profile, app, bundle) in [("photoshop", "Photoshop", "com.adobe.Photoshop"), ("pixelmator", "Pixelmator Pro", "com.pixelmatorteam.pixelmator.x"), ("affinity-photo", "Affinity Photo", "com.seriflabs.affinityphoto"), ("affinity-designer", "Affinity Designer", "com.seriflabs.affinitydesigner")] {
            func add(_ id: String, _ title: String, _ symbol: String, _ value: String, _ modifiers: [KeyModifier] = []) { key(profile, app, bundle, .photo, id, title, symbol, value, modifiers) }
            add("undo", "Undo", "arrow.uturn.backward", "z", [.command])
            add("redo", "Redo", "arrow.uturn.forward", "z", [.command, .shift])
            add("copy", "Copy", "doc.on.doc", "c", [.command])
            add("paste", "Paste", "doc.on.clipboard", "v", [.command])
            add("save", "Save", "square.and.arrow.down", "s", [.command])
            add("zoom-in", "Zoom in", "plus.magnifyingglass", "=", [.command])
            add("zoom-out", "Zoom out", "minus.magnifyingglass", "-", [.command])
            add("fit", "Fit canvas", "arrow.up.left.and.arrow.down.right", "0", [.command])
            add("fullscreen", profile == "photoshop" ? "Cycle screen mode" : "Fullscreen", "arrow.up.left.and.arrow.down.right", "f", profile == "photoshop" ? [] : [.control, .command])
            add("new", "New document", "doc.badge.plus", "n", [.command])
            add("open", "Open document", "folder", "o", [.command])
            add("export", profile == "photoshop" ? "Save for web" : "Export", "square.and.arrow.up", profile == "pixelmator" ? "e" : "s", profile == "pixelmator" ? [.command] : [.command, .option, .shift])
                    add("cut", "Cut", "scissors", "x", [.command])
            add("select-all", "Select all", "selection.pin.in.out", "a", [.command])
            add("duplicate", "Duplicate layer", "plus.square.on.square", "j", [.command])
            add("group", "Group layers", "square.stack.3d.up", "g", [.command])
            add("ungroup", "Ungroup layers", "square.stack.3d.down.right", "g", [.command, .shift])
            add("new-layer", "New layer", "square.badge.plus", "n", [.command, .shift])
            add("close", "Close document", "xmark.square", "w", [.command])
            add("move-tool", "Move tool", "cursorarrow", "v")
            add("picker-tool", "Color picker", "eyedropper", "i")
            add("brush-tool", "Brush", "paintbrush.pointed", "b")
            add("gradient-tool", "Gradient", "rectangle.lefthalf.filled", "g")
            add("pen-tool", "Pen", "pencil.tip", "p")
            add("text-tool", "Text", "textformat", "t")
            add("hand-tool", "Hand", "hand.draw", "h")
            add("zoom-tool", "Zoom", "magnifyingglass", "z")
            add("brush-smaller", "Smaller brush", "minus.circle", "[")
            add("brush-larger", "Larger brush", "plus.circle", "]")
            add("opacity-half", "50% opacity", "circle.lefthalf.filled", "5")
            add("opacity-full", "100% opacity", "circle.fill", "0")
            if profile == "photoshop" {
            add("crop-tool", "Crop", "crop", "c")
            add("marquee-tool", "Marquee selection", "rectangle.dashed", "m")
            add("lasso-tool", "Lasso selection", "lasso", "l")
            add("selection-tool", "Selection tools", "selection.pin.in.out", "w")
            add("erase-tool", "Eraser", "eraser", "e")
            add("heal-tool", "Healing tools", "bandage", "j")
            add("clone-tool", "Clone stamp", "square.on.square", "s")
            add("deselect", "Deselect", "rectangle.dashed", "d", [.command])
            add("invert-selection", "Invert selection", "square.dashed.inset.filled", "i", [.command, .shift])
            add("reselect", "Reselect", "selection.pin.in.out", "d", [.command, .shift])
            add("transform", "Free transform", "arrow.up.left.and.arrow.down.right", "t", [.command])
            add("levels", "Levels", "slider.horizontal.3", "l", [.command])
            add("curves", "Curves", "chart.xyaxis.line", "m", [.command])
            add("hue", "Hue / saturation", "paintpalette", "u", [.command])
            add("invert", "Invert colors", "circle.lefthalf.filled", "i", [.command])
            add("desaturate", "Desaturate", "drop", "u", [.command, .shift])
            add("merge-down", "Merge down", "square.3.layers.3d.down.right", "e", [.command])
            add("merge-visible", "Merge visible", "square.3.layers.3d", "e", [.command, .shift])
            add("clipping", "Clipping mask", "square.on.square", "g", [.command, .option])
            add("image-size", "Image size", "arrow.up.left.and.arrow.down.right", "i", [.command, .option])
            add("canvas-size", "Canvas size", "crop", "c", [.command, .option])
            add("swap-colors", "Swap colors", "arrow.triangle.2.circlepath", "x")
            add("reset-colors", "Reset colors", "circle.lefthalf.filled", "d")
            add("actual-size", "Actual size", "1.magnifyingglass", "1", [.command])
            add("rulers", "Rulers", "ruler", "r", [.command])
            }
            if profile == "pixelmator" {
            add("crop-tool", "Crop", "crop", "c")
            add("marquee-tool", "Rectangular selection", "rectangle.dashed", "m")
            add("lasso-tool", "Free selection", "lasso", "l")
            add("selection-tool", "Quick selection", "selection.pin.in.out", "q")
            add("color-selection-tool", "Color selection", "eyedropper", "w")
            add("ellipse-tool", "Elliptical selection", "circle.dashed", "y")
            add("erase-tool", "Eraser", "eraser", "e")
            add("repair-tool", "Repair", "bandage", "r")
            add("clone-tool", "Clone", "square.on.square", "o")
            add("fill-tool", "Color fill", "drop.fill", "n")
            add("adjustments", "Color adjustments", "slider.horizontal.3", "a")
            add("effects", "Effects", "sparkles", "f")
            add("style", "Style", "paintpalette", "s")
            add("shape-tool", "Shape", "square.on.circle", "u")
            add("image-size", "Image size", "arrow.up.left.and.arrow.down.right", "i", [.command, .option])
            add("canvas-size", "Canvas size", "crop", "c", [.command, .option])
            add("super-resolution", "Super Resolution", "sparkles", "u", [.command, .option])
            add("remove-background", "Remove background", "person.crop.rectangle", "delete", [.shift])
            add("replace-layer", "Replace layer", "arrow.triangle.2.circlepath", "r", [.command, .shift])
            add("merge-selected", "Merge selected layers", "square.3.layers.3d.down.right", "e", [.command, .option])
            add("merge-all", "Merge all layers", "square.3.layers.3d", "e", [.command, .option, .shift])
            add("lock", "Lock / unlock layer", "lock", "/")
            add("export-web", "Export for web", "globe", "e", [.command, .shift])
            add("actual-size", "Actual size", "1.magnifyingglass", "1", [.command])
            add("select-layers", "Select all layers", "square.stack.3d.up", "a", [.command, .option])
            }
            if profile == "affinity-photo" {
            add("crop-tool", "Crop", "crop", "c")
            add("marquee-tool", "Marquee selection", "rectangle.dashed", "m")
            add("lasso-tool", "Freehand selection", "lasso", "l")
            add("selection-tool", "Selection brush / flood select", "selection.pin.in.out", "w")
            add("erase-tool", "Eraser", "eraser", "e")
            add("retouch-tool", "Retouch tools", "bandage", "j")
            add("clone-tool", "Clone brush", "square.on.square", "k")
            add("smudge-tool", "Smudge brush", "hand.draw", "s")
            add("replace-color-tool", "Color replacement brush", "paintpalette", "r")
            add("pixel-tool", "Pixel tool", "square.grid.3x3", "y")
            add("dodge-tool", "Dodge / burn / sponge", "sun.max", "o")
            add("shape-tool", "Shape tools", "square.on.circle", "u")
            add("deselect", "Deselect", "rectangle.dashed", "d", [.command])
            add("invert-selection", "Invert selection", "square.dashed.inset.filled", "i", [.command, .shift])
            add("merge-down", "Merge down", "square.3.layers.3d.down.right", "e", [.command])
            add("invert", "Invert colors", "circle.lefthalf.filled", "i", [.command])
            add("snapping", "Snapping", "link", ";")
            add("lock", "Lock layer", "lock", "l", [.command])
            add("unlock", "Unlock layer", "lock.open", "l", [.command, .shift])
            add("reset-colors", "Reset colors", "circle.lefthalf.filled", "d")
            add("bring-forward", "Bring forward", "square.3.layers.3d.top.filled", "]", [.command])
            add("send-backward", "Send backward", "square.3.layers.3d.bottom.filled", "[", [.command])
            }
            if profile == "affinity-designer" {
            add("node-tool", "Node tool", "point.topleft.down.curvedto.point.bottomright.up", "a")
            add("point-transform-tool", "Point transform", "arrow.up.left.and.arrow.down.right", "f")
            add("contour-tool", "Contour", "square.on.square", "o")
            add("corner-tool", "Corner tool", "arrow.turn.down.right", "c")
            add("pencil-tool", "Pencil", "pencil", "n")
            add("stroke-tool", "Stroke width", "lineweight", "w")
            add("knife-tool", "Knife", "scissors", "k")
            add("transparency-tool", "Transparency", "circle.lefthalf.filled", "y")
            add("fill-tool", "Vector flood fill", "drop.fill", "r")
            add("shape-tool", "Shape tools", "square.on.circle", "m")
            add("builder-tool", "Shape builder", "square.stack.3d.up", "s")
            add("snapping", "Snapping", "link", ";")
            add("lock", "Lock object", "lock", "l", [.command])
            add("unlock", "Unlock object", "lock.open", "l", [.command, .shift])
            add("bring-forward", "Bring forward", "square.3.layers.3d.top.filled", "]", [.command])
            add("send-backward", "Send backward", "square.3.layers.3d.bottom.filled", "[", [.command])
            add("bring-front", "Bring to front", "square.3.layers.3d.top.filled", "]", [.command, .shift])
            add("send-back", "Send to back", "square.3.layers.3d.bottom.filled", "[", [.command, .shift])
            add("no-fill", "No fill", "circle.slash", "/")
            add("color-selector", "Switch fill / stroke", "arrow.triangle.2.circlepath", "x")
            }
        }
        func x(_ id: String, _ title: String, _ symbol: String, _ value: String, _ modifiers: [KeyModifier] = []) { key("xcode", "Xcode", "com.apple.dt.Xcode", .development, id, title, symbol, value, modifiers) }
        x("build", "Build", "hammer.fill", "b", [.command])
        x("run", "Run", "play.fill", "r", [.command])
        x("test", "Test", "checkmark.diamond", "u", [.command])
        x("stop", "Stop", "stop.fill", ".", [.command])
        x("debug", "Debug area", "ladybug", "y", [.command, .shift])
        x("breakpoint", "Toggle breakpoint", "record.circle", "\\", [.command])
        x("continue", "Continue", "play.fill", "y", [.control, .command])
        x("step-over", "Step over", "arrow.turn.up.right", "f6")
        x("step-into", "Step into", "arrow.down.to.line", "f7")
        x("step-out", "Step out", "arrow.up.to.line", "f8")
        x("project", "Open project", "folder", "o", [.command])
        x("format", "Re-indent selection", "text.alignleft", "i", [.control])
        x("comment", "Toggle comment", "text.bubble", "/", [.command])
        x("definition", "Go to definition", "arrow.up.forward.app", "j", [.control, .command])
        x("next-error", "Next issue", "exclamationmark.arrow.circlepath", "'", [.command])
        x("previous-error", "Previous issue", "exclamationmark.circle", "'", [.command, .shift])
        x("open-quickly", "Open quickly", "doc.text.magnifyingglass", "o", [.command, .shift])
        x("navigator", "Project navigator", "sidebar.left", "1", [.command])
        x("editor", "Choose editor", "chevron.left.forwardslash.chevron.right", "j", [.command])
        func v(_ id: String, _ title: String, _ symbol: String, _ value: String, _ modifiers: [KeyModifier] = []) { key("vscode", "VS Code", "com.microsoft.VSCode", .development, id, title, symbol, value, modifiers) }
        v("build", "Build task", "hammer.fill", "b", [.command, .shift])
        v("run", "Run without debugging", "play.fill", "f5", [.control])
        v("debug", "Start debugging", "ladybug", "f5")
        v("stop", "Stop debugging", "stop.fill", "f5", [.shift])
        v("breakpoint", "Toggle breakpoint", "record.circle", "f9")
        v("continue", "Continue", "play.fill", "f5")
        v("step-over", "Step over", "arrow.turn.up.right", "f10")
        v("step-into", "Step into", "arrow.down.to.line", "f11")
        v("step-out", "Step out", "arrow.up.to.line", "f11", [.shift])
        v("terminal", "Toggle terminal", "terminal", "`", [.control])
        v("project", "Open file or folder", "folder", "o", [.command])
        v("format", "Format document", "text.alignleft", "f", [.option, .shift])
        v("comment", "Toggle comment", "text.bubble", "/", [.command])
        v("definition", "Go to definition", "arrow.up.forward.app", "f12")
        v("references", "Find references", "point.3.connected.trianglepath.dotted", "f12", [.shift])
        v("next-error", "Next issue", "exclamationmark.arrow.circlepath", "f8")
        v("previous-error", "Previous issue", "exclamationmark.circle", "f8", [.shift])
        v("git-status", "Source control", "point.3.filled.connected.trianglepath.dotted", "g", [.control, .shift])
        v("recent", "Open recent file", "clock.arrow.circlepath", "p", [.command])
        v("editor", "Focus editor", "chevron.left.forwardslash.chevron.right", "1", [.command])
        v("navigator", "Explorer", "sidebar.left", "e", [.command, .shift])
        return result
    }()
    public static let actions: [LibraryAction] = {
        var items: [LibraryAction] = []
        func add(_ id: String, _ title: String, _ detail: String, _ category: ActionCategory, _ action: DeckAction, _ symbol: String) {
            items.append(LibraryAction(id: id, title: title, detail: detail, category: category, action: action, symbol: action.fixedSymbol ?? symbol))
        }
        add("app", "Mac app", "Open an application", .apps, .launchApp(bundleID: ""), "app")
        for provider in AgentProvider.allCases {
            add("agent." + provider.rawValue, provider.title, "Desktop and terminal activity", .ai, .agent(provider), provider.symbol)
        }
        add("website", "Website", "Open in your Mac’s browser", .apps, .website(url: "https://"), "globe")
        add("shortcut", "Apple Shortcut", "Run a shortcut on your Mac", .apps, .shortcut(identifier: ""), "square.stack.3d.up")
        add("assistant", "Assistant", "Speak a command for your Mac", .ai, .assistant, "waveform")
        add("timer", "Timer", "A countdown on your iPhone", .editing, .timer(seconds: 300), "timer")
        add("sequence", "Action sequence", "Run a bounded workflow", .editing, .sequence(.init(name: "Action sequence")), "list.bullet.rectangle")
        add("keyboard", "Keyboard shortcut", "Choose keys and a target app", .editing, .keyboard(.init()), "keyboard")
        add("media.playPause", "Play / pause", "Controls the Mac's active media player", .media, .media(.playPause), "playpause.fill")
        add("media.previous", "Previous track", "Controls the Mac's active media player", .media, .media(.previous), "backward.end.fill")
        add("media.next", "Next track", "Controls the Mac's active media player", .media, .media(.next), "forward.end.fill")
        add("dial.volume", "Volume dial", "Turn to adjust; tap to mute", .mac, .dial(.volume), "speaker.wave.2")
        add("dial.brightness", "Brightness dial", "Adjust your Mac’s display", .mac, .dial(.brightness), "sun.max")
        for (command, name, detail) in [
            (SystemCommand.lock, "Lock Mac", "Lock the current session"),
            (.sleepDisplay, "Sleep display", "Turn off the screen"),
            (.showDesktop, "Show desktop", "Use the Mac’s desktop shortcut"),
            (.darkMode, "Toggle appearance", "Switch light and dark mode"),
            (.screenshot, "Screenshot", "Capture the screen"),
            (.screenshotArea, "Capture area", "Choose an area on the Mac")
        ] { add("system." + command.rawValue, name, detail, .mac, .system(command), "desktopcomputer") }
        add("terminal", "Open Terminal", "Terminal on your Mac", .development, .launchApp(bundleID: "com.apple.Terminal"), "terminal")
        for (id, title, symbol, key, mods) in [
            ("undo", "Undo", "arrow.uturn.backward", "z", [KeyModifier.command]),
            ("redo", "Redo", "arrow.uturn.forward", "z", [.command, .shift]),
            ("copy", "Copy", "doc.on.doc", "c", [.command]),
            ("cut", "Cut", "scissors", "x", [.command]),
            ("paste", "Paste", "doc.on.clipboard", "v", [.command]),
            ("save", "Save", "square.and.arrow.down", "s", [.command]),
            ("find", "Find", "magnifyingglass", "f", [.command]),
            ("select-all", "Select all", "checkmark.rectangle.stack", "a", [.command]),
            ("new-tab", "New tab", "plus.square.on.square", "t", [.command]),
            ("close-tab", "Close tab", "xmark.square", "w", [.command]),
            ("fullscreen", "Toggle fullscreen", "arrow.up.left.and.arrow.down.right", "f", [.control, .command])
        ] { add("editing." + id, title, "Current app", .editing, .keyboard(.init(key: key, modifiers: mods)), symbol) }
        items += presets.map { LibraryAction(id: $0.id, title: $0.title, detail: $0.appName, category: $0.category, action: .preset($0.id), symbol: $0.symbol) }
        return items
    }()
}

extension KeyboardShortcut {
    public var displayText: String { modifiers.map(\.symbol).joined() + key.uppercased() }
}
