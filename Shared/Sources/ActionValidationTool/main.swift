import Foundation
import QuickTileCore

func csv(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
var rows = [["action_id", "title", "app_profile", "bundle_variants", "app_version", "os_version", "keymap", "required_context", "expected_effect", "verification_method", "result", "vendor_documentation"]]
for definition in ActionRegistry.definitions {
    let profile = definition.appProfileID.flatMap { AppProfiles.profile(id: $0) }
    let preset: ActionPreset? = { if case .preset(let id) = definition.action { return ActionLibrary.preset(id: id) }; return nil }()
    let keymap = preset?.shortcut?.displayText ?? { if case .keyboard(let key) = definition.action { return key.displayText }; return "" }()
    rows.append([definition.id, definition.title, profile?.id ?? "", profile?.bundleIDs.joined(separator: " | ") ?? "", "", "", keymap,
                 definition.context ?? "", definition.title,
                 definition.semantics == .commandSent ? "Vendor mapping + real app/document effect" : "Real state/result observation",
                 "PENDING", definition.documentationURL ?? ""])
}
let output = rows.map { $0.map(csv).joined(separator: ",") }.joined(separator: "\n") + "\n"
if CommandLine.arguments.count == 2 { try Data(output.utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic) }
else { print(output, terminator: "") }
