import SwiftUI
import UIKit
import WidgetKit
import QuickTileCore

struct ControlEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
    var boardID: String?
    var page = 1
    var lastFour = false
    var tileID: String?
    var pager: WidgetPageIntent? = nil
    func playbackSymbol(_ target: String) -> String { (snapshot.playback?.first(where: { $0.target == target })?.state ?? .unknown).controlSymbol }
}
private func controlTimeline(_ entry: ControlEntry) -> Timeline<ControlEntry> {
    var entries = [entry]
    if let date = entry.snapshot.feedbackDate, date.addingTimeInterval(31) > entry.date {
        var cleared = entry; cleared.date = date.addingTimeInterval(31); entries.append(cleared)
    }
    return .init(entries: entries, policy: .after(Date().addingTimeInterval(900)))
}
struct BoardProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ControlEntry { .init(date: Date(), snapshot: .empty) }
    func snapshot(for configuration: BoardWidgetConfiguration, in context: Context) async -> ControlEntry { entry(configuration, family: context.family) }
    func timeline(for configuration: BoardWidgetConfiguration, in context: Context) async -> Timeline<ControlEntry> { controlTimeline(entry(configuration, family: context.family)) }
    private func entry(_ config: BoardWidgetConfiguration, family: WidgetFamily) -> ControlEntry {
        let snapshot = WidgetStore.load()
        let board = config.board.flatMap { selected in snapshot.boards.first { $0.id == selected.id } } ?? (config.board == nil ? snapshot.boards.first : nil)
        var entry = ControlEntry(date: Date(), snapshot: snapshot, boardID: config.board?.id, page: config.page, lastFour: config.lastFour)
        guard let board, board.pages.indices.contains(config.page - 1) else { return entry }
        let small = family == .systemSmall
        let pager = WidgetPageIntent(boardID: board.id, page: config.page, half: config.lastFour, small: small)
        let count = board.pages.count * (small ? 2 : 1)
        let base = (config.page - 1) * (small ? 2 : 1) + (small && config.lastFour ? 1 : 0)
        let offset = WidgetStore.defaults?.integer(forKey: pager.key) ?? 0
        let panel = (base + offset % count + count) % count
        entry.page = small ? panel / 2 + 1 : panel + 1
        entry.lastFour = small && panel % 2 == 1
        entry.pager = count > 1 ? pager : nil
        return entry
    }
}
struct TileProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ControlEntry { .init(date: Date(), snapshot: .empty) }
    func snapshot(for configuration: TileWidgetConfiguration, in context: Context) async -> ControlEntry { .init(date: Date(), snapshot: WidgetStore.load(), tileID: configuration.tile?.id) }
    func timeline(for configuration: TileWidgetConfiguration, in context: Context) async -> Timeline<ControlEntry> { controlTimeline(await snapshot(for: configuration, in: context)) }
}
struct QuickProvider: TimelineProvider {
    func placeholder(in context: Context) -> ControlEntry { .init(date: Date(), snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (ControlEntry) -> Void) { completion(.init(date: Date(), snapshot: WidgetStore.load())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ControlEntry>) -> Void) { completion(controlTimeline(.init(date: Date(), snapshot: WidgetStore.load()))) }
}
struct WidgetTileButton: View {
    let tile: Tile
    var artwork: Data? = nil
    var playbackSymbol: String? = nil
    var body: some View {
        Group {
            if WidgetStore.needsApp(tile) { Link(destination: WidgetStore.url(tile)) { label } }
            else if case .dial = tile.action {
                HStack(spacing: 0) {
                    Button(intent: RunWidgetTile(tile.id.uuidString, adjustment: -5)) { Image(systemName: "minus").frame(maxWidth: .infinity, maxHeight: .infinity) }.accessibilityLabel("Decrease \(tile.name)")
                    if case .dial(.volume) = tile.action {
                        Button(intent: RunWidgetTile(tile.id.uuidString)) { Image(systemName: tile.displaySymbol).font(.caption).frame(maxHeight: .infinity) }.accessibilityLabel("Mute or restore volume")
                    } else { Image(systemName: tile.displaySymbol).font(.caption) }
                    Button(intent: RunWidgetTile(tile.id.uuidString, adjustment: 5)) { Image(systemName: "plus").frame(maxWidth: .infinity, maxHeight: .infinity) }.accessibilityLabel("Increase \(tile.name)")
                }
            } else { Button(intent: RunWidgetTile(tile.id.uuidString)) { label } }
        }
        .buttonStyle(.plain)
        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel(tile.name)
        .invalidatableContent()
    }
    private var label: some View {
        Group {
            if let playbackSymbol { PlaybackGlyph(symbol: playbackSymbol).font(.title2) }
            else if let artwork, let image = UIImage(data: artwork) { Image(uiImage: image).resizable().scaledToFit().padding(10) }
            else { Image(systemName: tile.displaySymbol).font(.title2) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
    }
}
struct WidgetSurface<Content: View>: View {
    let entry: ControlEntry
    let title: String
    var symbol = "desktopcomputer"
    var pager: WidgetPageIntent? = nil
    @ViewBuilder var content: Content
    private var headerText: String {
        if let feedback = entry.snapshot.feedback, let date = entry.snapshot.feedbackDate, entry.date.timeIntervalSince(date) < 30 { return feedback }
        return title
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: symbol); Text(headerText).lineLimit(1).frame(height: 18, alignment: .leading); Spacer(minLength: 0)
                if let pager { Button(intent: pager) { Image(systemName: "chevron.right").frame(width: 24, height: 24) }.buttonStyle(.plain).accessibilityLabel("Next tiles") }
            }.font(.caption.weight(.medium)).foregroundStyle(.secondary)
            if entry.snapshot.macID == nil {
                Link(destination: URL(string: "quicktile://widgets")!) { VStack(spacing: 6) { Image(systemName: "square.grid.2x2").font(.title); Text("Set up in QuickTile").font(.caption) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else { content }
        }.containerBackground(.background, for: .widget)
    }
}
struct BoardControlView: View {
    let entry: ControlEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        let board = entry.boardID.flatMap { id in entry.snapshot.boards.first { $0.id == id } } ?? (entry.boardID == nil ? entry.snapshot.boards.first : nil)
        WidgetSurface(entry: entry, title: board?.name ?? "Board removed", symbol: board?.symbol ?? "square.grid.2x2", pager: entry.pager) {
            if let board, board.pages.indices.contains(entry.page - 1) {
                let slots = board.pages[entry.page - 1]
                let visible = family == .systemSmall ? Array(slots.dropFirst(entry.lastFour ? 4 : 0).prefix(4)) : slots
                GeometryReader { geometry in
                    let columns = family == .systemMedium ? 4 : 2
                    let rows = max(1, (visible.count + columns - 1) / columns)
                    let height = max(1, (geometry.size.height - CGFloat(rows - 1) * 8) / CGFloat(rows))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                        ForEach(Array(visible.enumerated()), id: \.offset) { _, tile in
                            if let tile { WidgetTileButton(tile: tile, artwork: entry.snapshot.icons?[tile.id.uuidString], playbackSymbol: tile.playbackTarget.map { entry.playbackSymbol($0) }).frame(height: height) }
                            else { RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.06)).frame(height: height) }
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { Text("Choose a board and page in Edit Widget.").font(.caption).frame(maxHeight: .infinity) }
        }
    }
}
struct BoardControlWidget: Widget {
    let kind = "QuickTileBoard"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: BoardWidgetConfiguration.self, provider: BoardProvider()) { BoardControlView(entry: $0) }
            .configurationDisplayName("Board controls")
            .description("Your tiles on the Home Screen or in StandBy. Small widgets show four tiles. Use the arrow to see more.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
struct SingleTileWidget: Widget {
    let kind = "QuickTileSingle"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: TileWidgetConfiguration.self, provider: TileProvider()) { entry in
            WidgetSurface(entry: entry, title: entry.snapshot.macName) {
                if let id = entry.tileID, let tile = entry.snapshot.boards.flatMap(\.pages).flatMap({ $0 }).compactMap({ $0 }).first(where: { $0.id.uuidString == id }) { WidgetTileButton(tile: tile, artwork: entry.snapshot.icons?[tile.id.uuidString], playbackSymbol: tile.playbackTarget.map { entry.playbackSymbol($0) }) }
                else { Text("Choose a tile in Edit Widget.").font(.caption).frame(maxHeight: .infinity) }
            }
        }.configurationDisplayName("Single tile").description("One large control for an action you use often.").supportedFamilies([.systemSmall])
    }
}
struct MacControlsWidget: Widget {
    let kind = "QuickTileMacControls"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickProvider()) { entry in
            WidgetSurface(entry: entry, title: entry.snapshot.macName) {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Button(intent: RunWidgetTile("control.play")) { PlaybackGlyph(symbol: entry.playbackSymbol("system")).frame(maxWidth: .infinity, maxHeight: .infinity) }.accessibilityLabel("Toggle Mac playback")
                        Button(intent: RunWidgetTile("control.next")) { Image(systemName: "forward.fill").frame(maxWidth: .infinity, maxHeight: .infinity) }.accessibilityLabel("Next track")
                    }
                    ForEach(["volume", "brightness"], id: \.self) { kind in
                        HStack {
                            Button(intent: RunWidgetTile("control." + kind, adjustment: -5)) { Image(systemName: "minus").frame(maxWidth: .infinity, maxHeight: .infinity) }.accessibilityLabel("Decrease \(kind)")
                            if kind == "volume" {
                                Button(intent: RunWidgetTile("control.volume")) { Image(systemName: "speaker.wave.2.fill").frame(maxHeight: .infinity) }.accessibilityLabel("Mute or restore volume")
                            } else { Image(systemName: "sun.max.fill") }
                            Button(intent: RunWidgetTile("control." + kind, adjustment: 5)) { Image(systemName: "plus").frame(maxWidth: .infinity, maxHeight: .infinity) }.accessibilityLabel("Increase \(kind)")
                        }
                    }
                }.buttonStyle(.plain).font(.body).frame(maxHeight: .infinity)
            }
        }.configurationDisplayName("Mac controls").description("Playback, volume and brightness. Each step changes the current level by five percent.").supportedFamilies([.systemSmall, .systemMedium])
    }
}
@main struct QuickTileWidgetBundle: WidgetBundle {
    var body: some Widget { BoardControlWidget(); SingleTileWidget(); MacControlsWidget() }
}
