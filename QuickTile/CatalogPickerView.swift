import SwiftUI
import QuickTileCore
import os

struct CatalogPickerView: View {
    enum Kind { case app, shortcut }
    let kind: Kind
    var allowsForeground = false
    let choose: (String, String) -> Void
    @Binding var selection: String
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var results: [Choice] = []
    private struct Choice: Identifiable, Sendable {
        let id: String
        let name: String
        let iconVersion: String?
    }
    var body: some View {
        List {
            if allowsForeground {
                Button("Current foreground app") { selection = ""; choose("", ""); dismiss() }
            }
            ForEach(results) { item in
                Button {
                    selection = item.id; choose(item.id, item.name); model.feedback(.selection); dismiss()
                } label: {
                    HStack(spacing: 12) {
                        if let version = item.iconVersion {
                            RemoteIcon(source: .app(version), store: model.images, fallback: "app")
                                .frame(width: 36, height: 36).id(version)
                        } else {
                            Image(systemName: kind == .app ? "app" : "square.stack.3d.up")
                                .frame(width: 36, height: 36).foregroundStyle(.secondary)
                        }
                        Text(item.name).foregroundStyle(.primary).lineLimit(1)
                        Spacer()
                        if selection == item.id { Image(systemName: "checkmark").foregroundStyle(.primary) }
                    }.frame(minHeight: 44)
                }.accessibilityIdentifier("catalog-choice-\(item.id)")
            }
        }
        .navigationTitle(kind == .app ? "Mac apps" : "Mac shortcuts")
        .searchable(text: $search, prompt: kind == .app ? "Search Mac apps" : "Search shortcuts")
        .overlay { if results.isEmpty && !search.isEmpty { ContentUnavailableView.search(text: search) } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Refresh") { model.refreshCatalog() }.disabled(model.state != .connected) }
        }
        .task(id: search + model.catalogRevision.uuidString) {
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(180)) }
            guard !Task.isCancelled else { return }
            let signposter = OSSignposter(subsystem: "sahil.QuickTile", category: "Catalog")
            let interval = signposter.beginInterval("Catalog search")
            defer { signposter.endInterval("Catalog search", interval) }
            let choices = kind == .app
                ? model.apps.map { Choice(id: $0.id, name: $0.name, iconVersion: $0.iconVersion) }
                : model.shortcuts.map { Choice(id: $0.id, name: $0.name, iconVersion: nil) }
            let found = await Task.detached(priority: .userInitiated) {
                query.isEmpty ? choices : choices.filter { $0.name.localizedStandardContains(query) }
            }.value
            guard !Task.isCancelled else { return }; results = found
        }
    }
}
