import SwiftUI
import UIKit
import UniformTypeIdentifiers
import QuickTileCore

struct BoardDocument: FileDocument {
    static let type = UTType(exportedAs: "app.quicktile.board", conformingTo: .json)
    static var readableContentTypes: [UTType] { [type, .json, .data] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= 33_554_432 else { throw QuickTileError.invalid("Choose a QuickTile board file under 32 MB.") }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// Selection and management share one presentation rather than presenting a sheet
/// while a UIKit-backed Menu is still dismissing.
struct BoardPickerView: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    let selectedPageID: String?
    let choose: (String) -> Void
    let manage: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.layout?.pages ?? []) { board in
                    let pages = (model.layout?.screens ?? []).filter { $0.pageID == board.id }
                    Section {
                        ForEach(pages) { page in
                            Button { choose(page.id) } label: {
                                HStack(spacing: 14) {
                                    BoardIcon(board: board).frame(width: 26, height: 26)
                                    Text(pages.count == 1 ? board.name : page.name).foregroundStyle(.primary)
                                    Spacer()
                                    if selectedPageID == page.id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                                }.padding(.vertical, 4)
                            }
                            .accessibilityIdentifier("choose-page-\(page.id)")
                            .accessibilityAddTraits(selectedPageID == page.id ? [.isSelected] : [])
                        }
                    } header: { if pages.count > 1 { Text(board.name) } }
                }
                Section {
                    Button("Manage boards", systemImage: "square.grid.2x2", action: manage)
                }
            }
            .navigationTitle("Choose board").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct DeckEditorView: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var boardName = ""
    @State private var naming = false
    @State private var deleteBoard: DeckPage?
    @State private var importing = false
    @State private var exporting = false
    @State private var shareWarning = false
    @State private var exportBoardID: UUID?
    @State private var document = BoardDocument()
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.layout?.pages ?? []) { board in
                        NavigationLink { PageEditorView(pageID: board.id) } label: {
                            HStack(spacing: 14) {
                                BoardIcon(board: board).frame(width: 30, height: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(board.name)
                                    Text("\(board.tiles.count) tiles · \(board.slots.count / 8) pages").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 4)
                        }.accessibilityIdentifier("page-" + board.name)
                        .contextMenu {
                            Button("Duplicate board", systemImage: "plus.square.on.square") { model.duplicateBoard(board) }
                            Button("Export board", systemImage: "square.and.arrow.up") { exportBoardID = board.id; shareWarning = true }
                            Button("Move earlier", systemImage: "arrow.up") { move(board.id, by: -1) }.disabled(model.layout?.pages.first?.id == board.id)
                            Button("Move later", systemImage: "arrow.down") { move(board.id, by: 1) }.disabled(model.layout?.pages.last?.id == board.id)
                            Button("Delete board", systemImage: "trash", role: .destructive) { deleteBoard = board }.disabled(model.layout?.pages.count == 1)
                        }
                        .accessibilityAction(named: "Duplicate board") { model.duplicateBoard(board) }
                        .accessibilityAction(named: "Move earlier") { move(board.id, by: -1) }
                        .accessibilityAction(named: "Move later") { move(board.id, by: 1) }
                    }.onMove { from, to in model.layout?.pages.move(fromOffsets: from, toOffset: to) }
                }
                Section {
                    NavigationLink { PresetBoardGallery() } label: { Label("Preset boards", systemImage: "rectangle.stack.badge.plus") }.accessibilityIdentifier("presetBoards")
                    Button { boardName = ""; naming = true } label: { Label("New blank board", systemImage: "plus") }.accessibilityIdentifier("addPage")
                }
                Section {
                    Button { importing = true } label: { Label("Import boards", systemImage: "square.and.arrow.down") }
                    Button { exportBoardID = nil; shareWarning = true } label: { Label("Export boards", systemImage: "square.and.arrow.up") }
                } footer: { Text("Board files include names, website addresses, mappings, and custom icons. Connection credentials are never included.") }
            }
            .navigationTitle("Boards").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { EditButton().accessibilityLabel("Reorder boards") }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("New board", isPresented: $naming) {
                TextField("Board name", text: $boardName)
                Button("Cancel", role: .cancel) {}
                Button("Add") { model.layout?.pages.append(DeckPage(name: boardName.trimmingCharacters(in: .whitespacesAndNewlines))); model.feedback(.success) }
                    .disabled(boardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || boardName.count > 100)
            }
            .confirmationDialog("Delete \(deleteBoard?.name ?? "board")?", isPresented: Binding(get: { deleteBoard != nil }, set: { if !$0 { deleteBoard = nil } })) {
                Button("Delete board", role: .destructive) {
                    if let deleteBoard, (model.layout?.pages.count ?? 0) > 1 { model.removeBoard(deleteBoard.id) }
                    deleteBoard = nil; model.feedback(.rigid)
                }
            } message: { Text("This removes the board and all its tiles.") }
            .confirmationDialog("Export your boards?", isPresented: $shareWarning) {
                Button("Export") { Task { do { document = BoardDocument(data: try await model.exportBoards(boardID: exportBoardID)); exporting = true } catch { model.error = error.localizedDescription } } }
            } message: { Text("Website addresses and custom names may contain private information. Review them before sharing.") }
            .fileExporter(isPresented: $exporting, document: document, contentType: BoardDocument.type, defaultFilename: "QuickTile") { result in if case .failure(let error) = result { model.error = error.localizedDescription } }
            .fileImporter(isPresented: $importing, allowedContentTypes: BoardDocument.readableContentTypes) { result in
                Task {
                    do {
                        let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let data = try await Task.detached(priority: .userInitiated) {
                            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard size <= 33_554_432 else { throw QuickTileError.invalid("Choose a file under 32 MB.") }
                            return try Data(contentsOf: url)
                        }.value
                        try await model.importBoards(data); model.feedback(.success)
                    } catch { model.error = error.localizedDescription }
                }
            }
        }
    }
    private func move(_ id: UUID, by offset: Int) {
        guard let index = model.layout?.pages.firstIndex(where: { $0.id == id }), let count = model.layout?.pages.count, (0..<count).contains(index + offset) else { return }
        model.layout?.pages.swapAt(index, index + offset); model.feedback(.selection)
    }
}

struct BoardIcon: View {
    let board: DeckPage
    @EnvironmentObject private var model: PhoneModel
    var body: some View {
        if let reference = board.customIconReference { RemoteIcon(source: .custom(reference), store: model.images, fallback: board.symbol) }
        else { Image(systemName: board.symbol).symbolRenderingMode(.hierarchical) }
    }
}

struct PageEditorView: View {
    let pageID: UUID
    @EnvironmentObject private var model: PhoneModel
    @State private var editing: Tile?
    @State private var adding = false
    @State private var boardNameDraft = ""
    private var index: Int? { model.layout?.pages.firstIndex { $0.id == pageID } }
    private var page: DeckPage? { model.layout?.pages.first { $0.id == pageID } }
    var body: some View {
        List {
            Section("Board settings") {
                TextField("Board name", text: $boardNameDraft).submitLabel(.done).onSubmit(commitName)
                NavigationLink {
                    IconSettingsView(symbol: Binding(get: { page?.symbol ?? "square.grid.2x2" }, set: { if let index { model.layout?.pages[index].symbol = $0 } }), reference: Binding(get: { page?.customIconReference }, set: { if let index { model.layout?.pages[index].customIconReference = $0 } }))
                } label: { Label { Text("Board icon") } icon: { if let page { BoardIcon(board: page).frame(width: 24, height: 24) } } }.accessibilityIdentifier("boardIcon")
                Picker("Linked app", selection: Binding(get: { page?.linkedAppProfileID ?? "" }, set: { value in if let index { model.layout?.pages[index].linkedAppProfileID = value.isEmpty ? nil : value; if value.isEmpty { model.layout?.pages[index].automaticSwitch = false } } })) {
                    Text("None").tag("")
                    ForEach(AppProfiles.profiles) { profile in Text(profile.title).tag(profile.id) }
                }
                Toggle("Switch when app becomes active", isOn: Binding(get: { page?.automaticSwitch == true }, set: { enabled in
                    guard let index else { return }
                    if enabled, let profile = page?.linkedAppProfileID, let indices = model.layout?.pages.indices {
                        for other in indices where other != index && model.layout?.pages[other].linkedAppProfileID == profile { model.layout?.pages[other].automaticSwitch = false }
                    }
                    model.layout?.pages[index].automaticSwitch = enabled
                })).disabled(page?.linkedAppProfileID == nil)
            }
            Section("Pages") {
                ForEach(0..<((page?.slots.count ?? 8) / 8), id: \.self) { screen in
                    HStack {
                        Text(pageName(screen))
                        Spacer()
                        pageActions(screen)
                    }
                }
                Button("Add blank page", systemImage: "plus") { model.addPage(boardID: pageID) }
            }
            Section {
                ForEach(page?.slots.compactMap { $0 } ?? []) { tile in
                    Button { editing = tile } label: {
                        HStack(spacing: 14) { Image(systemName: tile.displaySymbol).frame(width: 26); Text(tile.name).foregroundStyle(.primary); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }.padding(.vertical, 6)
                    }.accessibilityIdentifier("tile-edit-" + tile.name)
                    .contextMenu {
                        Button("Duplicate tile", systemImage: "plus.square.on.square") { model.duplicateTile(tile, boardID: pageID) }
                        Button("Move earlier", systemImage: "arrow.up") { move(tile.id, -1) }
                        Button("Move later", systemImage: "arrow.down") { move(tile.id, 1) }
                        Menu("Move to board") { ForEach((model.layout?.pages ?? []).filter { $0.id != pageID }) { board in Button { moveToBoard(tile, board.id) } label: { Label { Text(board.name) } icon: { BoardIcon(board: board).frame(width: 20, height: 20) } } } }
                        Button("Remove tile", systemImage: "trash", role: .destructive) { model.removeTile(tile, boardID: pageID) }
                    }
                    .accessibilityAction(named: "Duplicate tile") { model.duplicateTile(tile, boardID: pageID) }
                    .accessibilityAction(named: "Move earlier") { move(tile.id, -1) }
                    .accessibilityAction(named: "Move later") { move(tile.id, 1) }
                }.onDelete { offsets in
                    let ordered = page?.slots.compactMap { $0 } ?? []
                    for offset in offsets where ordered.indices.contains(offset) { model.removeTile(ordered[offset], boardID: pageID) }
                }.onMove { source, destination in
                    guard let index, let layout = model.layout else { return }
                    var order = layout.pages[index].slots.map { $0?.id }
                    let populated = order.indices.filter { order[$0] != nil }
                    var compact = order.compactMap { $0 }; compact.move(fromOffsets: source, toOffset: destination)
                    for (position, slot) in populated.enumerated() { order[slot] = compact[position] }
                    model.layout?.pages[index].tileOrder = order; model.feedback(.selection)
                }
                Button { adding = true } label: { Label("Add tile", systemImage: "plus") }.accessibilityIdentifier("addTile")
            } header: { Text("Tiles") } footer: { Text("Eight tiles fit on each page. Hold a tile on the board to move it, or reorder here.") }
            Section {
                Button { if let page { model.duplicateBoard(page) } } label: { Label("Duplicate board", systemImage: "plus.square.on.square") }.disabled(page == nil)
                if model.undoAvailable { Button("Undo removal") { model.undoRemoval() } }
            }
        }
        .navigationTitle(page?.name ?? "Board").navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton().accessibilityLabel("Reorder tiles") }
        .sheet(isPresented: $adding) { TileEditorView(pageID: pageID, tile: nil) }
        .sheet(item: $editing) { tile in TileEditorView(pageID: pageID, tile: tile) }
        .onAppear { if boardNameDraft.isEmpty { boardNameDraft = page?.name ?? "" } }.onDisappear(perform: commitName)
    }
    private func pageActions(_ number: Int) -> some View {
        Menu {
            Button("Duplicate page") { model.duplicatePage(boardID: pageID, index: number) }
            Button("Remove page", role: .destructive) { model.removePage(boardID: pageID, index: number) }.disabled((page?.slots.count ?? 8) == 8)
        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
            .accessibilityLabel("\(pageName(number)) actions")
    }
    private func pageName(_ number: Int) -> String {
        if let names = page?.pageNames, names.indices.contains(number) { return names[number] }
        return "Page \(number + 1)"
    }
    private func commitName() {
        let value = boardNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index, (try? Validation.name(value)) != nil { model.layout?.pages[index].name = value }
    }
    private func move(_ id: UUID, _ offset: Int) {
        guard let index, let slot = page?.slots.firstIndex(where: { $0?.id == id }), let count = page?.slots.count, (0..<count).contains(slot + offset) else { return }
        model.layout?.pages[index].place(id, at: slot + offset); model.feedback(.selection)
    }
    private func moveToBoard(_ tile: Tile, _ destination: UUID) {
        guard let target = model.layout?.pages.firstIndex(where: { $0.id == destination }), let index, var layout = model.layout else { return }
        layout.pages[index].removeTile(tile.id); layout.pages[target].tiles.append(tile); model.layout = layout; model.feedback(.selection)
    }
}

struct PresetBoardGallery: View {
    @State private var query = ""
    private var boards: [PresetBoard] { PresetBoards.boards.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        List {
            ForEach(boards) { board in
                NavigationLink { PresetBoardPreview(board: board) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: board.symbol).font(.title3).frame(width: 32)
                        VStack(alignment: .leading, spacing: 3) { Text(board.title); Text(board.pages.map(\.name).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 5)
                }.accessibilityIdentifier("preset-board-" + board.id)
            }
            if boards.isEmpty { ContentUnavailableView.search(text: query) }
        }.navigationTitle("Preset boards").navigationBarTitleDisplayMode(.inline).searchable(text: $query, prompt: "Search apps or workflows")
    }
}

private struct PresetBoardPreview: View {
    let board: PresetBoard
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var preferredBundleID = ""
    private var candidates: [AppEntry] { board.profileID.map { AppProfiles.candidates(profileID: $0, apps: model.apps) } ?? [] }
    var body: some View {
        List {
            Section {
                Text(board.prerequisites).font(.callout).foregroundStyle(.secondary)
                if board.profileID != nil && candidates.isEmpty {
                    Label(model.state == .connected ? "App not found on this Mac" : "Connect to check installed apps", systemImage: "exclamationmark.circle").font(.callout)
                }
                if candidates.count > 1 {
                    Picker("Default app", selection: $preferredBundleID) { Text("Choose app").tag(""); ForEach(candidates) { Text($0.name).tag($0.id) } }
                }
            } footer: { Text("Adds an editable copy. Future preset changes never overwrite your board.") }
            ForEach(board.pages) { page in
                Section(page.name) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(Array(page.actionIDs.enumerated()), id: \.offset) { _, id in
                            if let action = ActionLibrary.actions.first(where: { $0.id == id }) {
                                VStack(spacing: 8) { Image(systemName: action.symbol).font(.title2).frame(height: 30); Text(action.title).font(.caption).multilineTextAlignment(.center).lineLimit(2) }
                                    .frame(maxWidth: .infinity).frame(height: 88).background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }.padding(.vertical, 6)
                }
            }
        }.navigationTitle(board.title).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button("Add board") {
                model.addPresetBoard(board, preferredBundleID: preferredBundleID.isEmpty ? nil : preferredBundleID)
                model.feedback(.success); dismiss()
            }.disabled(candidates.count > 1 && preferredBundleID.isEmpty).accessibilityIdentifier("addPresetBoard")
        } }
    }
}
