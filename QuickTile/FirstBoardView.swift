import SwiftUI
import QuickTileCore

struct FirstBoardView: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { PresetBoardGallery() } label: { Label("Choose a preset board", systemImage: "rectangle.stack.badge.plus") }
                    Button { dismiss() } label: { Label("Start with a blank board", systemImage: "square.dashed") }
                } header: { Text("Your Mac is paired") } footer: { Text("Presets add an editable copy. You can add boards and tiles anytime.") }
            }.navigationTitle("Add your first board").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
