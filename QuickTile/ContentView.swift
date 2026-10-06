import SwiftUI
import UIKit
import QuickTileCore
import os

struct ContentView: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pageID: String?
    @State private var showMacs = false
    @State private var showEditor = false
    @State private var showBoardPicker = false
    @State private var selectedPageAfterDismiss: String?
    @State private var showSettings = false
    @State private var editingTile: TileEditRequest?
    @State private var deletingTile: TileEditRequest?
    @State private var editingScreen: String?
    @State private var addingSlot: AddSlot?
    @State private var slotFrames: [Int: CGRect] = [:]
    @State private var gridFrame = CGRect.zero
    @State private var heldSlot: Int?
    @State private var draggedTile: Tile?
    @State private var dragStart = CGPoint.zero
    @State private var dragPreview = TileDragPreview()
    @State private var hoveredSlot: Int?
    private var dragPoint: CGPoint {
        get { dragPreview.point }
        nonmutating set { dragPreview.move(to: newValue) }
    }
    @State private var dragFrame = CGRect.zero
    @State private var draggedBoardID: UUID?
    @State private var edgeDirection = 0
    @State private var edgeTask: Task<Void, Never>?
    @State private var appSwitchTask: Task<Void, Never>?
    @State private var dialing = false
    @State private var assistantActive = false
    @State private var movingTile: TileEditRequest?
    @State private var settling = false
    @State private var switchingAutomatically = false
    private struct AddSlot: Identifiable {
        let pageID: UUID
        let slot: Int
        var id: String { "\(pageID)-\(slot)" }
    }
    private struct TileEditRequest: Identifiable {
        let pageID: UUID
        let tile: Tile
        var id: UUID { tile.id }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button { showMacs = true } label: {
                        Image(systemName: "desktopcomputer").font(.title3)
                            .frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("\(model.selected?.name ?? "Choose a Mac"), \(model.state.label)").accessibilityIdentifier("macPicker")
                    Spacer(minLength: 16)
                    if model.previewMode { Text("Preview").font(.caption.weight(.medium)).foregroundStyle(.secondary) }
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                        .accessibilityLabel("Settings").accessibilityIdentifier("settings")
                }.padding(.horizontal, 24).padding(.top, 4)
                if let layout = model.layout {
                    deck(layout)
                } else {
                    welcome
                }
                ZStack {
                    ActivityStatus(message: model.activity).padding(.horizontal, 60).frame(maxWidth: .infinity)
                    if model.undoAvailable {
                        HStack { Spacer(); Button("Undo") { model.undoRemoval() }.font(.caption.weight(.medium)).frame(minWidth: 44, minHeight: 44).accessibilityLabel("Undo removal") }
                    }
                }.frame(height: 44).padding(.horizontal, 24)
            }
            .onReceive(model.assistant.$phase) { assistantActive = $0 != .idle }
            .onReceive(model.assistant.$issue) { if let issue = $0 { model.error = issue } }
            .onReceive(model.assistant.$message) { model.assistantFeedback($0) }
            .background(Color(uiColor: .systemGroupedBackground))
            .background(PageHoldGesture(enabled: model.layout != nil && editingScreen == nil && !settling && !showMacs && !showSettings && !showEditor && editingTile == nil && addingSlot == nil && model.error == nil && model.agentRequestProvider == nil && !model.scanning && !model.macPaused && !dialing && !assistantActive, pageScrollingEnabled: editingScreen == nil && !dialing, acceptsTouch: { point in
                guard gridFrame.contains(point) else { return false }
                if let (slot, frame) = slotFrames.first(where: { $0.value.contains(point) }), let tile = currentScreen?.slots[slot], case .timer = tile.action {
                    return !CGRect(x: frame.maxX - 44, y: frame.maxY - 44, width: 44, height: 44).contains(point)
                }
                return true
            }, preview: { point in
                dragStart = point; dragPoint = point
                model.prepareEditFeedback()
                heldSlot = slotFrames.first { $0.value.contains(point) }?.key
            }, began: {
                guard let screen = currentScreen else { return }
                if let heldSlot, let tile = screen.slots[heldSlot], let frame = slotFrames[heldSlot] {
                    dragPreview.show(frame: frame, start: dragStart, alreadyShrunk: true)
                    draggedTile = tile; draggedBoardID = screen.pageID; dragFrame = frame
                }
                beginEditing(screen.id)
            }, moved: { updateDrag($0) }, ended: { commit in
                if commit, let tile = draggedTile, let screen = currentScreen { commitDrag(tile, screen: screen) }
                else { finishDrag() }
            }))
            .onPreferenceChange(SlotFrames.self) { frames in
                let screen = UIScreen.main.bounds
                slotFrames = frames.filter { $0.value.intersects(screen) }
            }
            .onPreferenceChange(GridFrame.self) { gridFrame = $0 }
            .overlay { TileDragPreviewHost(preview: dragPreview).allowsHitTesting(false).accessibilityHidden(true) }
            .task {
                while !Task.isCancelled {
                    model.timers.tick(tiles: model.layout?.pages.flatMap(\.tiles) ?? []) { id, pattern in model.playTimerHaptic(pattern, timerID: id) }
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { break }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showMacs) { MacPickerView() }
            .sheet(isPresented: $showEditor, onDismiss: {
                if let selectedPageAfterDismiss {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { pageID = selectedPageAfterDismiss }
                    self.selectedPageAfterDismiss = nil
                }
                showBoardPicker = false
                model.clearRemovalHistory()
            }) {
                if showBoardPicker {
                    BoardPickerView(selectedPageID: currentScreen?.id, choose: { id in
                        selectedPageAfterDismiss = id
                        showEditor = false
                    }, manage: { showBoardPicker = false })
                } else { DeckEditorView() }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: Binding(get: { model.agentRequestProvider != nil }, set: { if !$0 { model.closeAgentRequests() } })) {
                AgentRequestView().environmentObject(model)
            }
            .sheet(isPresented: $model.choosingFirstBoard) { FirstBoardView() }
            .sheet(item: $editingTile) { request in TileEditorView(pageID: request.pageID, tile: request.tile) }
            .sheet(item: $addingSlot) { request in TileEditorView(pageID: request.pageID, tile: nil, insertionSlot: request.slot) }
            .sheet(item: $movingTile) { request in MoveTileView(boardID: request.pageID, tile: request.tile) }
            .confirmationDialog("Delete this tile?", isPresented: Binding(get: { deletingTile != nil }, set: { if !$0 { deletingTile = nil } })) {
                Button("Delete tile", role: .destructive) {
                    if let request = deletingTile { model.removeTile(request.tile, boardID: request.pageID) }
                    deletingTile = nil
                }
            }
            .alert("Use Groq for voice commands?", isPresented: Binding(get: { model.assistantConsentTile != nil }, set: { if !$0 { model.assistantConsentTile = nil } })) {
                Button("Cancel", role: .cancel) { model.assistantConsentTile = nil }
                Button("Use assistant") { model.approveAssistant() }
            } message: {
                Text("Your transcript and available Mac app and Shortcut names will be sent to Groq. Audio stays on your iPhone. Commands run on your paired Mac using your Groq account.")
            }
            .sheet(isPresented: $model.scanning) { QRScannerView { model.pair($0) } }
            .overlay(alignment: .top) {
                if let error = model.error {
                    Notice(message: error) {
                        model.error = nil
                        model.feedback(.soft)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : -6)))
                    .zIndex(20)
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.24, extraBounce: 0), value: model.error != nil)
            .onChange(of: model.error) { _, message in
                if let message { UIAccessibility.post(notification: .announcement, argument: message) }
            }
            .onChange(of: model.agentRequestProvider) { _, provider in if provider != nil { model.assistant.cancel() } }
            .onChange(of: showMacs) { _, shown in if shown { model.assistant.cancel(); model.feedback(.soft) } }
            .onChange(of: showSettings) { _, shown in if shown { model.assistant.cancel(); model.feedback(.soft) } }
            .onChange(of: showEditor) { _, shown in if shown { model.assistant.cancel(); model.feedback(.soft) } }
            .onChange(of: editingScreen) { old, new in
                if old != nil && new == nil { model.clearRemovalHistory() }
            }
            .onChange(of: pageID) { old, new in if old != new { model.feedback(.selection); if !switchingAutomatically { appSwitchTask?.cancel() }; switchingAutomatically = false } }
            .onChange(of: model.frontmostBundleID) { _, bundleID in scheduleAppSwitch(bundleID) }
            .onDisappear { edgeTask?.cancel(); appSwitchTask?.cancel() }
            .onReceive(model.controls.$error) { message in if let message { model.error = message } }
            .overlay {
                if model.macPaused { PausedOverlay().transition(.opacity).zIndex(10) }
            }
        }
    }
    private struct Notice: View {
        let message: String
        let dismiss: () -> Void
        var body: some View {
            HStack(spacing: 12) {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
                Spacer(minLength: 0)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.quaternary, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss message")
                .accessibilityIdentifier("dismissNotice")
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("notice")
        }
    }
    private var currentScreen: DeckScreen? { model.layout?.screens.first { $0.id == pageID } ?? model.layout?.screens.first }

    private struct PausedOverlay: View {
        @EnvironmentObject private var model: PhoneModel
        var body: some View {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                VStack(spacing: 14) {
                    Image(systemName: "pause.circle.fill").font(.system(size: 54, weight: .light)).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
                    Text("QuickTile is paused").font(.title3.weight(.semibold))
                    Text("Resume connections on your Mac to use these tiles.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 250)
                    Button("Refresh connection") { model.retry(); model.feedback(.soft) }
                        .buttonStyle(.borderedProminent).tint(.primary).foregroundStyle(Color(uiColor: .systemBackground))
                }.padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous)).padding(28)
            }.accessibilityElement(children: .contain).accessibilityLabel("QuickTile is paused. Resume connections on your Mac to use these tiles.")
        }
    }
    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "square.grid.2x2").font(.system(size: 60, weight: .ultraLight)).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Pair your Mac").font(.title2.weight(.semibold))
                Text("Use apps, shortcuts, and controls from your iPhone.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button { model.scanning = true } label: { Label("Pair with your Mac", systemImage: "qrcode.viewfinder").font(.subheadline.weight(.semibold)).padding(.horizontal, 24).padding(.vertical, 14) }
                .buttonStyle(.borderedProminent).tint(.primary).foregroundStyle(Color(uiColor: .systemBackground)).accessibilityIdentifier("pairMac")
            Button("Find nearby Macs") { showMacs = true }.font(.subheadline).frame(minHeight: 44)
            Button("Preview board") { model.enterPreview() }.font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("previewBoard")
            Spacer()
            Text("Run the QuickTile companion on your Mac.\nConnect both devices to the same local network.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.bottom, 24)
        }.padding(.horizontal, 28).frame(maxWidth: .infinity)
    }
    private func deck(_ layout: DeckLayout) -> some View {
        let screens = layout.screens
        return VStack(spacing: 0) {
            GeometryReader { viewport in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                ForEach(screens) { page in
                    GeometryReader { proxy in
                        let landscape = proxy.size.width > proxy.size.height
                        let columns = landscape ? 4 : 2
                        let rows = landscape ? 2 : 4
                        let gap = TileMetrics.gap
                        let inset = TileMetrics.gridInset
                        let width = max(1, (proxy.size.width - inset * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns))
                        let height = max(1, (proxy.size.height - inset * 2 - gap * CGFloat(rows - 1)) / CGFloat(rows))
                        Group {
                            if page.tiles.isEmpty && editingScreen == nil {
                                VStack(spacing: 16) {
                                    Image(systemName: "square.dashed").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(.tertiary)
                                    Text("Add your first tile").font(.headline)
                                    Text("Choose an app, shortcut, or control.").font(.subheadline).foregroundStyle(.secondary)
                                    Button("Edit page") { beginEditing(page.id) }.frame(minHeight: 44).accessibilityIdentifier("emptyEditDeck")
                                    Button("Preset boards") { showEditor = true }.font(.subheadline).frame(minHeight: 44)
                                }.frame(maxWidth: .infinity, minHeight: max(200, proxy.size.height - 48)).padding(.horizontal, 20)
                            } else {
                                VStack(spacing: gap) {
                                    ForEach(0..<rows, id: \.self) { row in
                                        HStack(spacing: gap) {
                                            ForEach(0..<columns, id: \.self) { column in
                                                let index = row * columns + column
                                                Group {
                                                if let tile = page.slots[index] {
                                                    occupiedSlot(page, tile: tile, index: index, width: width, height: height)
                                                } else if editingScreen == page.id {
                                                    editableSlot(page, index: index, width: width, height: height)
                                                } else {
                                                    RoundedRectangle(cornerRadius: TileMetrics.cornerRadius, style: .continuous)
                                                        .strokeBorder(.primary.opacity(0.045), lineWidth: 1)
                                                        .frame(width: width, height: height).accessibilityHidden(true)
                                                }
                                                }
                                                // Keep the source slot visible until the floating drag copy is ready.
                                                .opacity(draggedTile?.id == page.slots[index]?.id && dragFrame.width > 0 ? 0.25 : 1)
                                                .overlay {
                                                    if draggedTile != nil, hoveredSlot == index {
                                                        RoundedRectangle(cornerRadius: TileMetrics.cornerRadius).strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2).allowsHitTesting(false)
                                                    }
                                                }
                                                .scaleEffect(heldSlot == index && draggedTile == nil && page.slots[index] != nil ? 0.96 : 1)
                                                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: heldSlot)
                                                .background(GeometryReader { geometry in
                                                    Color.clear.preference(key: SlotFrames.self, value: page.id == (pageID ?? screens.first?.id) ? [index: geometry.frame(in: .global)] : [:])
                                                })
                                            }
                                        }
                                    }
                                }.padding(inset)
                            }
                        }
                    }.frame(width: viewport.size.width, height: viewport.size.height).id(page.id)
                }
                }.scrollTargetLayout()
            }.scrollTargetBehavior(.paging).scrollIndicators(.hidden)
                .scrollPosition(id: Binding(get: { pageID ?? screens.first?.id }, set: { newValue in if editingScreen == nil { pageID = newValue } }))
                .scrollDisabled(editingScreen != nil || dialing || assistantActive)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: pageID)
                .accessibilityIdentifier("deckPager")
            }
                .clipped()
                .background(GeometryReader { proxy in Color.clear.preference(key: GridFrame.self, value: proxy.frame(in: .global)) })
            HStack(spacing: 0) {
                let current = screens.first { $0.id == pageID } ?? screens.first
                Button {
                    showBoardPicker = true
                    showEditor = true
                } label: {
                    Group {
                        if let board = model.layout?.pages.first(where: { $0.id == current?.pageID }) { BoardIcon(board: board).frame(width: 23, height: 23) }
                        else { Image(systemName: "square.grid.2x2").font(.title3) }
                    }.frame(width: 44, height: 44)
                }
                    .disabled(editingScreen != nil || assistantActive)
                    .accessibilityLabel("Board: \(current?.name ?? "My board"). Choose page.").accessibilityIdentifier("pageMenu")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if screens.count > 1 && editingScreen == nil {
                        DeckPageDots(count: screens.count, selection: Binding(get: { screens.firstIndex { $0.id == current?.id } ?? 0 }, set: { pageID = screens[$0].id }))
                            .accessibilityIdentifier("pageDots")
                    } else { Color.clear.accessibilityHidden(true) }
                }.frame(maxWidth: .infinity).frame(height: 44)
                Button {
                    if editingScreen != nil {
                        var transaction = Transaction(); transaction.disablesAnimations = true
                        withTransaction(transaction) { editingScreen = nil }
                        model.feedback(.soft)
                    } else if let id = current?.id {
                        beginEditing(id)
                    }
                } label: { Image(systemName: editingScreen == nil ? "square.and.pencil" : "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel(editingScreen == nil ? "Edit page" : "Done editing").accessibilityIdentifier("editDeck")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }.padding(.horizontal, 24)
        }.onChange(of: screens.map(\.id)) { _, ids in if let pageID, !ids.contains(pageID) { self.pageID = ids.first } }
    }
    private func beginEditing(_ id: String) {
        model.assistant.cancel()
        guard editingScreen == nil else { return }
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { pageID = id; editingScreen = id }
        model.feedback(.editMode)
    }
    @ViewBuilder private func occupiedSlot(_ page: DeckScreen, tile: Tile, index: Int, width: CGFloat, height: CGFloat) -> some View {
        let editing = editingScreen == page.id
        Group {
            if case .assistant = tile.action {
                AssistantTileView(id: tile.id, store: model.assistant) { model.activateAssistant(tile) }
                    .frame(width: width, height: height).allowsHitTesting(!editing)
                    .overlay { if editing { editHitTarget(page, tile: tile) } }
            } else if case .timer(let seconds) = tile.action {
                TimerTileView(id: tile.id, seconds: seconds, store: model.timers, feedback: { model.feedback($0) })
                    .frame(width: width, height: height).allowsHitTesting(!editing)
                    .overlay { if editing { editHitTarget(page, tile: tile) } }
            } else if case .dial(let kind) = tile.action {
                ControlDial(kind: kind, store: model.controls, interactionChanged: { dialing = $0 })
                    .padding(max(8, min(width, height) * 0.08))
                    .frame(width: width, height: height)
                    .background(TileMetrics.surface, in: RoundedRectangle(cornerRadius: TileMetrics.cornerRadius))
                    .allowsHitTesting(!editing)
                    .overlay { if editing { editHitTarget(page, tile: tile) } }
            } else {
                Button {
                    if editing { editingTile = TileEditRequest(pageID: page.pageID, tile: tile) }
                    else { model.execute(tile) }
                } label: {
                    TileFace(tile: tile, labels: false, iconSize: min(TileMetrics.maximumIcon, min(width, height) * 0.64))
                        .frame(width: width, height: height)
                }
                .buttonStyle(TilePressStyle(reduceMotion: reduceMotion))
                .disabled(!editing && model.busyTiles.contains(tile.id))
                .accessibilityLabel(editing ? "Edit \(tile.name)" : tileAccessibilityLabel(tile))
                .accessibilityIdentifier("deck-tile-\(tile.id)")
            }
        }
        .contentShape(Rectangle())
        .highPriorityGesture(DragGesture(minimumDistance: 6).onChanged { value in
            guard editing, let frame = slotFrames[index] else { return }
            if draggedTile == nil {
                dragStart = CGPoint(x: frame.minX + value.startLocation.x, y: frame.minY + value.startLocation.y)
                dragPreview.show(frame: frame, start: dragStart)
                draggedTile = tile; heldSlot = index; draggedBoardID = page.pageID; dragFrame = frame
            }
            updateDrag(CGPoint(x: frame.minX + value.location.x, y: frame.minY + value.location.y))
        }.onEnded { _ in
            guard let moving = draggedTile, let screen = currentScreen else { return }
            commitDrag(moving, screen: screen)
        }, including: editing ? .all : .none)
        .overlay(alignment: .topTrailing) {
            if editing {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { model.removeTile(tile, boardID: page.pageID) }
            } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Circle()).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Remove \(tile.name)")
            }
        }
        .modifier(EditWiggle(active: editing && !reduceMotion, phase: index))
        .accessibilityAction(named: "Edit tile") { editingTile = TileEditRequest(pageID: page.pageID, tile: tile) }
        .accessibilityAction(named: "Delete tile") { deletingTile = TileEditRequest(pageID: page.pageID, tile: tile) }
        .accessibilityAction(named: "Duplicate tile") { model.duplicateTile(tile, boardID: page.pageID) }
        .accessibilityAction(named: "Move tile") { movingTile = TileEditRequest(pageID: page.pageID, tile: tile) }
    }
    private func editHitTarget(_ page: DeckScreen, tile: Tile) -> some View {
        Button { editingTile = TileEditRequest(pageID: page.pageID, tile: tile) } label: { Color.clear.contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel("Edit \(tile.name)")
    }
    private func editableSlot(_ page: DeckScreen, index: Int, width: CGFloat, height: CGFloat) -> some View {
        Button { addingSlot = AddSlot(pageID: page.pageID, slot: page.index * 8 + index); model.feedback(.soft) } label: {
            Image(systemName: "plus").font(.title2.weight(.regular)).foregroundStyle(.secondary)
                .frame(width: width, height: height)
                .background(TileMetrics.surface, in: RoundedRectangle(cornerRadius: TileMetrics.cornerRadius))
        }.buttonStyle(.plain).accessibilityLabel("Add tile in slot \(index + 1)")
    }
    private func commitDrag(_ tile: Tile, screen: DeckScreen) {
        if let destination = slotFrames.first(where: { $0.value.contains(dragPoint) })?.key,
           var layout = model.layout, let board = layout.pages.firstIndex(where: { $0.id == screen.pageID }) {
            if let sourceID = draggedBoardID, sourceID != screen.pageID, let source = layout.pages.firstIndex(where: { $0.id == sourceID }) {
                let displaced = layout.pages[board].slots[screen.index * 8 + destination]
                let sourceSlot = layout.pages[source].slots.firstIndex(where: { $0?.id == tile.id })
                layout.pages[source].removeTile(tile.id); layout.pages[board].tiles.append(tile)
                if let displaced, let sourceSlot {
                    layout.pages[board].removeTile(displaced.id); layout.pages[source].tiles.append(displaced)
                    layout.pages[source].place(displaced.id, at: sourceSlot)
                }
            }
            layout.pages[board].place(tile.id, at: screen.index * 8 + destination)
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.16)) {
                model.layout = layout
                if let frame = slotFrames[destination] { dragPreview.move(to: CGPoint(x: frame.midX + dragStart.x - dragFrame.midX, y: frame.midY + dragStart.y - dragFrame.midY), animated: !reduceMotion) }
            }
            model.feedback(.rigid)
            if !reduceMotion {
                settling = true; edgeTask?.cancel()
                Task { @MainActor in try? await Task.sleep(for: .milliseconds(160)); finishDrag() }
                return
            }
        }
        finishDrag()
    }
    private func tileAccessibilityLabel(_ tile: Tile) -> String {
        if case .agent(let provider) = tile.action {
            return "\(provider.title), \(model.agentSnapshot(provider,source:tile.agentSource)?.phase.label ?? AgentPhase.unknown.label)"
        }
        return tile.name
    }
    private func finishDrag() {
        edgeTask?.cancel(); edgeTask = nil; edgeDirection = 0
        dragPreview.hide(); hoveredSlot = nil
        draggedTile = nil; heldSlot = nil; draggedBoardID = nil; dragFrame = .zero
        settling = false
    }
    private func updateDrag(_ point: CGPoint) {
        dragPoint = point
        let destination = slotFrames.first { $0.value.contains(point) }?.key
        if hoveredSlot != destination { hoveredSlot = destination }
        guard draggedTile != nil, let grid = slotFrames.values.reduce(nil as CGRect?, { $0?.union($1) ?? $1 }) else { return }
        let direction = point.x < grid.minX + 26 ? -1 : point.x > grid.maxX - 26 ? 1 : 0
        guard direction != edgeDirection else { return }
        edgeTask?.cancel(); edgeDirection = direction
        guard direction != 0 else { return }
        edgeTask = Task { @MainActor in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
                guard draggedTile != nil, edgeDirection == direction, let screens = model.layout?.screens, let current = screens.firstIndex(where: { $0.id == pageID }), screens.indices.contains(current + direction) else { return }
                let next = screens[current + direction].id
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { pageID = next; editingScreen = next }
                model.feedback(.selection)
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
        }
    }
    private func scheduleAppSwitch(_ bundleID: String?) {
        appSwitchTask?.cancel()
        guard let bundleID else { return }
        appSwitchTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard model.frontmostBundleID == bundleID, editingScreen == nil, draggedTile == nil, !dialing,
                  !showMacs, !showSettings, !showEditor, !assistantActive, model.agentRequestProvider == nil, editingTile == nil, addingSlot == nil, movingTile == nil, !model.scanning,
                  let board = model.layout?.pages.first(where: { $0.automaticSwitch == true && $0.linkedAppProfileID.map { AppProfiles.matches(profileID: $0, bundleID: bundleID) } == true }),
                  let screen = model.layout?.screens.first(where: { $0.pageID == board.id }) else { return }
            switchingAutomatically = true
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { pageID = screen.id }
        }
    }

}
/// Touch-frequency movement stays in UIKit; the board changes only when the
/// destination slot changes or the tile is dropped.
@MainActor private final class TileDragPreview {
    private let signposter = OSSignposter(subsystem: "sahil.QuickTile", category: "Editing")
    private var interval: OSSignpostIntervalState?
    private weak var host: UIView?
    private var snapshot: UIView?
    private var origin = CGPoint.zero
    private var start = CGPoint.zero
    private(set) var point = CGPoint.zero
    func attach(_ host: UIView) { self.host = host }
    func show(frame: CGRect, start: CGPoint, alreadyShrunk: Bool = false) {
        hide()
        guard let host, let window = host.window,
              let snapshot = window.resizableSnapshotView(from: window.convert(frame, from: nil), afterScreenUpdates: false, withCapInsets: .zero) else { return }
        let local = host.convert(window.convert(frame, from: nil), from: window)
        self.start = start; point = start; origin = CGPoint(x: local.midX, y: local.midY)
        snapshot.bounds = CGRect(origin: .zero, size: frame.size)
        snapshot.center = origin
        snapshot.transform = CGAffineTransform(scaleX: alreadyShrunk ? 1 : 0.96, y: alreadyShrunk ? 1 : 0.96)
        snapshot.isUserInteractionEnabled = false
        snapshot.layer.shadowColor = UIColor.black.cgColor
        snapshot.layer.shadowOpacity = 0.18; snapshot.layer.shadowRadius = 12
        snapshot.layer.shadowOffset = CGSize(width: 0, height: 6)
        snapshot.layer.shadowPath = UIBezierPath(roundedRect: snapshot.bounds, cornerRadius: TileMetrics.cornerRadius).cgPath
        host.addSubview(snapshot); self.snapshot = snapshot
        interval = signposter.beginInterval("Tile drag")
    }
    func move(to point: CGPoint, animated: Bool = false) {
        self.point = point
        guard let snapshot else { return }
        let center = CGPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y)
        if animated {
            UIView.animate(withDuration: 0.16, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) { snapshot.center = center }
        } else { snapshot.center = center }
    }
    func hide() {
        snapshot?.removeFromSuperview(); snapshot = nil
        if let interval { signposter.endInterval("Tile drag", interval); self.interval = nil }
    }
}
private struct TileDragPreviewHost: UIViewRepresentable {
    let preview: TileDragPreview
    func makeUIView(context: Context) -> UIView {
        let view = UIView(); view.isUserInteractionEnabled = false
        preview.attach(view); return view
    }
    func updateUIView(_ view: UIView, context: Context) {}
}

private struct SlotFrames: PreferenceKey {
    static var defaultValue: [Int: CGRect] { [:] }
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
private struct GridFrame: PreferenceKey {
    static var defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { let next = nextValue(); if next != .zero { value = next } }
}
private struct EditWiggle: ViewModifier {
    let active: Bool
    let phase: Int
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !active)) { context in
            let angle = active ? sin(context.date.timeIntervalSinceReferenceDate * (20 + Double(phase % 3)) + Double(phase)) * 0.65 : 0
            content.rotationEffect(.degrees(angle))
                .animation(nil, value: active)
        }
    }
}
private struct ControlDial: View {
    let kind: ControlKind
    private var symbol: String {
        if kind == .volume { return value <= 0 ? "speaker.slash.fill" : value >= 1 ? "speaker.wave.3.fill" : "speaker.wave.2" }
        return value <= 0 ? "sun.min" : value >= 1 ? "sun.max.fill" : "sun.max"
    }
    @ObservedObject var store: MacControlStore
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var value = 0.0
    @State private var dragging = false
    @State private var lastAngle: Double?
    @State private var lastStop: Int?
    var interactionChanged: (Bool) -> Void = { _ in }
    init(kind: ControlKind, store: MacControlStore, interactionChanged: @escaping (Bool) -> Void = { _ in }) {
        self.kind = kind; self.store = store
        self.interactionChanged = interactionChanged
        _value = State(initialValue: store.value(kind) ?? 0)
    }
    private var enabled: Bool { store.available && (kind == .volume ? store.state?.volume : store.state?.brightness) != nil }
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2 - 13
            ZStack {
                Circle()
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    .overlay(Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(dragging ? 0.06 : 0.16), radius: dragging ? 2 : 6, y: dragging ? 1 : 4)
                    .scaleEffect(dragging ? 0.97 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: dragging)
                    .padding(19)
                Circle().trim(from: 0, to: 0.75).stroke(.primary.opacity(0.09), style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(135)).padding(13)
                Circle().trim(from: 0, to: 0.75 * value).stroke(.primary.opacity(0.85), style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(135)).padding(13)
                ForEach(0..<21) { tick in
                    Capsule().fill(.primary.opacity(Double(tick) / 20 <= value ? 0.5 : 0.13))
                        .frame(width: 1.5, height: 5)
                        .offset(y: -size / 2 + 2)
                        .rotationEffect(.degrees(225 + Double(tick) * 13.5))
                }
                Image(systemName: symbol).font(.system(size: size * 0.19, weight: .regular))
                    .overlay {
                        if kind == .brightness && value <= 0 {
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: size * 0.24))
                                path.addLine(to: CGPoint(x: size * 0.24, y: 0))
                            }.stroke(.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .frame(width: size * 0.24, height: size * 0.24)
                        }
                    }.accessibilityHidden(true)
                Circle().fill(.primary).frame(width: 10, height: 10)
                    .offset(x: radius * cos((135 + value * 270) * .pi / 180), y: radius * sin((135 + value * 270) * .pi / 180))
            }.frame(width: size, height: size).contentShape(Circle())
                .opacity(enabled ? 1 : 0.3)
                .highPriorityGesture(DragGesture(minimumDistance: 4).onChanged { gesture in
                    guard enabled else { return }
                    if !dragging { dragging = true; interactionChanged(true); lastStop = nil; model.feedback(.dialTick) }
                    let x = gesture.location.x - size / 2, y = gesture.location.y - size / 2
                    guard hypot(x, y) > size * 0.18 else { lastAngle = nil; return }
                    let angle = atan2(y, x)
                    if let lastAngle {
                        var delta = angle - lastAngle
                        if delta > .pi { delta -= .pi * 2 }; if delta < -.pi { delta += .pi * 2 }
                        change(value + delta / (.pi * 1.5))
                    }
                    lastAngle = angle
                }.onEnded { _ in dragging = false; interactionChanged(false); lastAngle = nil })
                .onTapGesture { toggleMute() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(kind == .volume ? "Mac volume" : "Mac brightness")
                .accessibilityValue(enabled ? "\(Int((value * 100).rounded())) percent" : "Unavailable")
                .accessibilityIdentifier(kind == .volume ? "volumeDial" : "brightnessDial")
                .accessibilityHint(kind == .volume ? "Tap to mute or restore volume. Rotate to adjust." : "Rotate clockwise to increase, counterclockwise to decrease")
                .accessibilityAction { toggleMute() }
                .accessibilityAdjustableAction { direction in
                    guard enabled else { return }
                    switch direction { case .increment: change(value + 0.05); case .decrement: change(value - 0.05); @unknown default: break }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { value = store.value(kind) ?? 0 }
        .onDisappear { interactionChanged(false) }
        .onChange(of: store.state) { _, _ in if !dragging { value = store.value(kind) ?? 0 } }
    }
    private func toggleMute() {
        guard kind == .volume, enabled, let next = store.toggleVolume() else { return }
        value = next
        model.feedback(next == 0 ? .dialLimit : .dialTick)
    }
    private func change(_ proposed: Double) {
        let next = min(1, max(0, proposed))
        let stop: Int? = next == 0 ? 0 : next == 1 ? 1 : nil
        if let stop, lastStop != stop { model.feedback(.dialLimit) }
        lastStop = stop
        guard next != value else { return }
        if stop == nil && Int(next * 20) != Int(value * 20) { model.feedback(.dialTick) }
        value = next; store.adjust(kind, value: next)
    }
}
private struct ActivityStatus: UIViewRepresentable {
    let message: String?
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.alpha = 0
        return label
    }
    func updateUIView(_ label: UILabel, context: Context) {
        guard context.coordinator.message != message else { return }
        context.coordinator.message = message
        label.layer.removeAllAnimations()
        label.isAccessibilityElement = message != nil
        if let message {
            label.text = message
            label.accessibilityLabel = "Action status: \(message)"
            label.alpha = 1
        } else {
            // Keep the glyphs intact until the compositor finishes the fade.
            UIView.animate(withDuration: 0.35, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut, .allowUserInteraction]) {
                label.alpha = 0
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var message: String? }
}
private struct DeckPageDots: UIViewRepresentable {
    let count: Int
    @Binding var selection: Int
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.currentPageIndicatorTintColor = .label
        control.pageIndicatorTintColor = .tertiaryLabel
        control.hidesForSinglePage = true
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return control
    }
    func updateUIView(_ control: UIPageControl, context: Context) {
        context.coordinator.parent = self
        control.numberOfPages = count
        control.currentPage = selection
    }
    final class Coordinator: NSObject {
        var parent: DeckPageDots
        init(_ parent: DeckPageDots) { self.parent = parent }
        @objc func changed(_ control: UIPageControl) { parent.selection = control.currentPage }
    }
}
struct TileFace: View {
    let tile: Tile
    var labels = true
    var iconSize: CGFloat = 72
    private var iconOnly: Bool {
        switch tile.action { case .launchApp, .website: return true; default: return false }
    }
    @EnvironmentObject private var model: PhoneModel
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if case .timer(let seconds) = tile.action {
                    VStack(spacing: 8) {
                        Image(systemName: "timer").font(.title2)
                        Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).font(.title2.monospacedDigit())
                    }
                } else if case .agent(let provider) = tile.action {
                    let snapshot = model.agentSnapshot(provider, source: tile.agentSource)
                    Image(systemName: provider.symbol)
                        .font(.system(size: iconSize * 0.55, weight: .regular))
                        .foregroundStyle(.primary)
                    Circle().fill(snapshot?.phase == .waiting ? Color.orange : snapshot?.phase == .running ? Color.green : Color.secondary)
                        .frame(width: 11, height: 11).overlay(Circle().stroke(.background, lineWidth: 2))
                        .offset(x: iconSize * 0.36, y: iconSize * 0.36)
                } else if let reference = tile.customIconReference {
                    RemoteIcon(source: .custom(reference), store: model.images, fallback: tile.displaySymbol)
                } else if case .launchApp(let id) = tile.action,
                   let version = (model.appByID[id] ?? AppProfiles.resolve(bundleID: id, apps: model.apps))?.iconVersion {
                    RemoteIcon(source: .app(version), store: model.images, fallback: tile.symbol).id(version)
                } else if case .website(let url) = tile.action, tile.symbol == "globe" {
                    RemoteIcon(source: .website(WebsiteIcons.origin(url)?.absoluteString ?? url), store: model.images, fallback: "globe").id(url)
                } else {
                    let symbol = tile.playbackTarget == nil ? tile.displaySymbol : model.playbackSymbol(for: tile)
                    Image(systemName: symbol).font(.system(size: iconSize * 0.55, weight: .regular)).foregroundStyle(.primary)
                        .contentTransition(.symbolEffect(.replace, options: .speed(2.5)))
                        .animation(.snappy(duration: 0.14), value: symbol)
                }
                if model.busyTiles.contains(tile.id) {
                    if let progress = model.sequenceProgress[tile.id] {
                        ProgressView(value: Double(progress.stepIndex), total: Double(max(1, progress.stepCount))).progressViewStyle(.circular).frame(width: 24, height: 24).padding(6).background(.regularMaterial, in: Circle())
                    } else { ProgressView().padding(6).background(.regularMaterial, in: Circle()) }
                }
            }.frame(width: iconSize, height: iconSize)
                if case .agent(let provider) = tile.action {
                    Text(model.agentSnapshot(provider, source: tile.agentSource)?.phase.label ?? AgentPhase.unknown.label)
                        .font(.caption2.weight(.medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
            }
            if labels && !iconOnly { Text(tile.name).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TileMetrics.surface, in: RoundedRectangle(cornerRadius: TileMetrics.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TileMetrics.cornerRadius).stroke(.primary.opacity(0.025), lineWidth: 1))
        .accessibilityLabel(agentAccessibilityLabel ?? tile.name)
        .accessibilityElement(children: .ignore)
    }
    private var agentAccessibilityLabel: String? {
        guard case .agent(let provider) = tile.action else { return nil }
        return "\(provider.title), \(model.agentSnapshot(provider, source: tile.agentSource)?.phase.label ?? AgentPhase.unknown.label)"
    }
}
struct TilePressStyle: ButtonStyle {
    var reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct TimerTileView: View {
    let id: UUID
    let seconds: Int
    @ObservedObject var store: TileTimerStore
    let feedback: (PhoneModel.Feedback) -> Void
    var body: some View {
        let value = store.value(id, seconds: seconds)
        let remaining = Int(ceil(value.remaining))
        ZStack(alignment: .bottomTrailing) {
            Button {
                store.toggle(id, seconds: seconds)
                feedback(value.finished ? .success : .soft)
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: value.finished ? "checkmark" : value.deadline == nil ? "play.fill" : "pause.fill")
                        .font(.system(size: 20, weight: .medium))
                        .contentTransition(.symbolEffect(.replace, options: .speed(2.5)))
                    Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                        .font(.system(size: 32, weight: .medium, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.5).lineLimit(1)
                }
                .foregroundStyle(value.finished ? Color.accentColor : .primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(value.finished ? "Timer finished. Acknowledge" : value.deadline == nil ? "Start timer" : "Pause timer")
                .accessibilityValue("\(remaining / 60) minutes, \(remaining % 60) seconds")
            if value.deadline != nil || value.remaining != Double(seconds) || value.finished {
                Button {
                    store.reset(id, seconds: seconds); feedback(.rigid)
                } label: { Image(systemName: "arrow.counterclockwise").font(.system(size: 14, weight: .medium)).frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Reset timer")
            }
        }
        .background(TileMetrics.surface, in: RoundedRectangle(cornerRadius: TileMetrics.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: TileMetrics.cornerRadius).strokeBorder(value.finished ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1.5))
    }
}
