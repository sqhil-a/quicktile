import SwiftUI
import QuickTileCore

struct MoveTileView: View {
    let boardID: UUID
    let tile: Tile
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(model.layout?.pages ?? []) { board in
                    Section(board.name) {
                        ForEach(0..<board.slots.count / 8, id: \.self) { page in
                            NavigationLink("Page \(page + 1)") {
                                List {
                                    ForEach(0..<8, id: \.self) { slot in
                                        Button {
                                            model.moveTile(tile, from: boardID, to: board.id, slot: page * 8 + slot); dismiss()
                                        } label: {
                                            HStack { Text("Slot \(slot + 1)"); Spacer(); Text(board.slots[page * 8 + slot]?.name ?? "Empty").foregroundStyle(.secondary) }
                                        }
                                    }
                                }.navigationTitle("Move tile").navigationBarTitleDisplayMode(.inline)
                            }
                        }
                    }
                }
            }.navigationTitle("Move \(tile.name)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
