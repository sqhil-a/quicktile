import Foundation
import QuickTileCore

/// Model output can only reach existing, available actions. No generated scripts or keys.
enum AssistantPlanValidation {
    static func validate(_ plans: [AssistantCommandPlan], capabilities: Capabilities, apps: [AppEntry], shortcuts: [ShortcutEntry]) throws {
        guard (1...8).contains(plans.count) else { throw QuickTileError.invalid("Use no more than eight actions.") }
        var controls = Set<ControlKind>()
        for plan in plans {
            try plan.action.validate()
            if let quit = plan.quitBundleID {
                guard case .launchApp(let target) = plan.action, target == quit, plan.targetBundleID == quit,
                      apps.contains(where: { $0.id == quit }) else { throw QuickTileError.invalid("Choose an installed app to quit.") }
            }
            let availability = ActionRegistry.availability(action: plan.action, capabilities: capabilities, apps: apps, connected: true, preferredBundleID: plan.targetBundleID)
            guard availability.isReady else { throw QuickTileError.failed(availability.message ?? "This control is unavailable.") }
            switch plan.action {
            case .assistant, .sequence, .agent, .timer, .music: throw QuickTileError.unsupported("This action is not available through the assistant.")
            case .dial(let kind):
                guard let value = plan.controlValue, value.isFinite, (0...1).contains(value), kind != .brightness || plan.displayID != nil else { throw QuickTileError.invalid("Choose a supported control level.") }
                guard controls.insert(kind).inserted else { throw QuickTileError.invalid("Use one final level for each control in a request.") }
                if kind == .volume, value == 0, !capabilities.mute { throw QuickTileError.unsupported("This output needs its hardware mute control.") }
            case .keyboard(let keys):
                guard keys.targetBundleID != nil else { throw QuickTileError.invalid("Choose the target app for keys.") }
            case .shortcut(let id):
                guard shortcuts.contains(where: { $0.id == id }) else { throw QuickTileError.failed("Refresh the Mac's shortcuts.") }
            default: break
            }
            if plan.desiredPlayback != nil, plan.targetBundleID.flatMap(MediaPlayer.init(rawValue:)) == nil { throw QuickTileError.unsupported("Choose a supported player.") }
        }
    }
}
