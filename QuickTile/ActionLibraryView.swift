import SwiftUI
import QuickTileCore

struct ActionLibraryView: View {
    var choose: (LibraryAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var category: ActionCategory? = nil
    var appName: String? = nil
    @AppStorage("recentActions") private var recentIDs = ""
    private var results: [LibraryAction] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = text.split(whereSeparator: \.isWhitespace)
        return ActionLibrary.actions.filter { item in (category == nil || item.category == category) && (appName == nil || item.preset?.appName == appName) && terms.allSatisfy { "\(item.title) \(item.detail) \(item.category.rawValue)".localizedCaseInsensitiveContains($0) } }
    }
    var body: some View {
        List {
            if let category, query.isEmpty {
                let items = ActionLibrary.actions.filter { $0.category == category }
                if (category == .video || category == .photo || category == .development), appName == nil {
                    ForEach(Array(Set(items.compactMap { $0.preset?.appName })).sorted(), id: \.self) { app in
                        NavigationLink {
                            ActionLibraryView(choose: choose, category: category, appName: app)
                        } label: {
                            Label(app, systemImage: category.symbol).padding(.vertical, 6)
                        }.accessibilityIdentifier((category == .video ? "video-app-" : category == .photo ? "photo-app-" : "development-app-") + app)
                    }
                    let general = items.filter { $0.preset == nil }
                    if !general.isEmpty { Section("General") { ForEach(general) { row($0) } } }
                } else if let appName {
                    let appItems = items.filter { $0.preset?.appName == appName }
                    if category == .development { ForEach(appItems) { row($0) } }
                    else {
                    ForEach(category == .photo ? ["Tools", "Selections & layers", "Color & retouch", "View & document"] : ["Playback", "Editing", "Tools & workspace", "Project"], id: \.self) { group in
                        let grouped = appItems.filter { (category == .photo ? photoGroup($0) : videoGroup($0)) == group }
                        if !grouped.isEmpty { Section(group) { ForEach(grouped) { row($0) } } }
                    }
                    Section { Text(category == .photo ? "Uses the app’s default Mac shortcuts. Keep the canvas focused. Designer tools use the Designer persona." : "Uses the app’s default Mac shortcuts. Keep the timeline or viewer focused.").font(.caption).foregroundStyle(.secondary) }
                    }
                } else {
                ForEach(Array(Dictionary(grouping: items, by: { $0.preset?.appName ?? ($0.category == .video || $0.category == .photo ? "Other" : "QuickTile") }).keys.sorted()), id: \.self) { app in
                    Section(app) { ForEach(items.filter { ($0.preset?.appName ?? ($0.category == .video || $0.category == .photo ? "Other" : "QuickTile")) == app }) { row($0) } }
                }
                }
            } else if query.isEmpty {
                let recent = recentIDs.split(separator: "|").compactMap { id in ActionLibrary.actions.first { $0.id == id } }
                if !recent.isEmpty { Section("Recent") { ForEach(recent) { row($0) } } }
                ForEach(ActionCategory.allCases) { category in
                    NavigationLink { ActionLibraryView(choose: choose, category: category) } label: {
                        Label(category.rawValue, systemImage: category.symbol).padding(.vertical, 6)
                    }.foregroundStyle(.primary)
                }
                if let sequence = ActionLibrary.actions.first(where: { $0.id == "sequence" }) { Section { row(sequence) } }
            } else {
                ForEach(results) { row($0) }
                if results.isEmpty { ContentUnavailableView.search(text: query) }
            }
        }
        .navigationTitle(appName ?? category?.rawValue ?? "Add tile")
        .searchable(text: $query, prompt: "Search actions or apps")
        .toolbar { ToolbarItem(placement: .cancellationAction) {
            if category == nil { Button("Cancel") { dismiss() } }
        } }
    }
    private func photoGroup(_ item: LibraryAction) -> String {
        let id = item.id.split(separator: ".").last.map(String.init) ?? ""
        if id.hasSuffix("-tool") { return "Tools" }
        if ["levels", "curves", "hue", "invert", "desaturate", "adjustments", "effects", "style", "super-resolution", "remove-background", "reset-colors", "swap-colors", "color-selector", "no-fill", "brush-smaller", "brush-larger", "opacity-half", "opacity-full"].contains(id) { return "Color & retouch" }
        if ["new", "open", "save", "close", "export", "export-web", "zoom-in", "zoom-out", "fit", "fullscreen", "image-size", "canvas-size", "actual-size", "rulers"].contains(id) { return "View & document" }
        return "Selections & layers"
    }
    private func videoGroup(_ item: LibraryAction) -> String {
        let id = item.id.split(separator: ".").last.map(String.init) ?? ""
        if ["play", "frame-back", "frame-forward", "start", "end", "reverse", "stop", "forward", "loop", "range-start", "range-end", "ten-back", "ten-forward", "next-edit", "previous-edit", "next-keyframe", "previous-keyframe"].contains(id) { return "Playback" }
        if ["save", "save-as", "open", "close", "new", "new-comp", "comp-settings", "import", "export", "render"].contains(id) { return "Project" }
        if id.hasSuffix("-tool") || id.hasSuffix("-page") || ["viewer", "timeline", "inspector", "zoom-in", "zoom-out", "fit", "graph", "position", "scale", "rotation", "opacity", "anchor", "effects", "masks", "keyframes"].contains(id) { return "Tools & workspace" }
        return "Editing"
    }
    private func row(_ item: LibraryAction) -> some View {
        Button {
            var ids = recentIDs.split(separator: "|").map(String.init).filter { $0 != item.id }
            ids.insert(item.id, at: 0); recentIDs = ids.prefix(6).joined(separator: "|")
            choose(item)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: item.symbol).font(.title3).frame(width: 30).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).foregroundStyle(.primary)
                    if appName == nil { Text(item.detail).font(.caption).foregroundStyle(.secondary) }
                }
            }.padding(.vertical, 4)
        }.accessibilityIdentifier("library-action-" + item.id)
    }
}
