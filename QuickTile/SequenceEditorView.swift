import SwiftUI
import QuickTileCore

struct SequenceEditorView: View {
    @Binding var sequence: ActionSequence
    @EnvironmentObject private var model: PhoneModel
    var body: some View {
        Section {
            ForEach(Array(sequence.steps.enumerated()), id: \.offset) { index, step in
                NavigationLink {
                    SequenceStepEditor(existing: step) { if sequence.steps.indices.contains(index) { sequence.steps[index] = $0 } }
                } label: { Label("\(index + 1). \(step.title)", systemImage: "circle") }
                    .contextMenu {
                        Button("Duplicate step", systemImage: "plus.square.on.square") { if sequence.steps.count < 12 { sequence.steps.insert(step, at: index + 1) } }.disabled(sequence.steps.count >= 12)
                        Button("Move earlier", systemImage: "arrow.up") { if index > 0 { sequence.steps.swapAt(index, index - 1) } }.disabled(index == 0)
                        Button("Move later", systemImage: "arrow.down") { if index + 1 < sequence.steps.count { sequence.steps.swapAt(index, index + 1) } }.disabled(index + 1 == sequence.steps.count)
                        Button("Remove step", systemImage: "trash", role: .destructive) { sequence.steps.remove(at: index) }
                    }
            }.onDelete { sequence.steps.remove(atOffsets: $0) }.onMove { sequence.steps.move(fromOffsets: $0, toOffset: $1) }
            NavigationLink { SequenceStepEditor { sequence.steps.append($0) } } label: { Label("Add step", systemImage: "plus") }.disabled(sequence.steps.count >= 12)
        } header: { Text("Steps") } footer: { Text("Up to 12 steps. Keyboard steps require a target app. Stops at the first failure; cancelling cannot undo completed steps.") }
    }
}

private struct SequenceStepEditor: View {
    var existing: SequenceStep? = nil
    let save: (SequenceStep) -> Void
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind = Kind.app
    @State private var target = ""
    @State private var shortcut = ""
    @State private var key = "space"
    @State private var modifiers: [KeyModifier] = []
    @State private var website = "https://"
    @State private var seconds = 1.0
    @State private var error: String?
    enum Kind: String, CaseIterable { case app = "Open app", keyboard = "Send keys", website = "Open website", shortcut = "Apple Shortcut", wait = "Wait" }
    var body: some View {
        Form {
            Picker("Step", selection: $kind) { ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            switch kind {
            case .app, .keyboard:
                NavigationLink(model.appByID[target]?.name ?? "Choose target app") { CatalogPickerView(kind: .app, choose: { _, _ in }, selection: $target) }
                if kind == .keyboard {
                    Picker("Key", selection: $key) { ForEach(KeyboardShortcut.keyCodes.keys.sorted(), id: \.self) { Text($0.uppercased()).tag($0) } }
                    ForEach(KeyModifier.allCases, id: \.self) { modifier in Toggle(modifier.symbol + " " + modifier.rawValue.capitalized, isOn: Binding(get: { modifiers.contains(modifier) }, set: { enabled in modifiers.removeAll { $0 == modifier }; if enabled { modifiers.append(modifier) } })) }
                }
            case .website: TextField("https://example.com", text: $website).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            case .shortcut: NavigationLink(model.shortcuts.first { $0.id == shortcut }?.name ?? "Choose shortcut") { CatalogPickerView(kind: .shortcut, choose: { _, _ in }, selection: $shortcut) }
            case .wait: Stepper("\(seconds.formatted()) seconds", value: $seconds, in: 0.5...10, step: 0.5)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Sequence step").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") {
            let step: SequenceStep = switch kind {
            case .app: .launchApp(bundleID: target)
            case .keyboard: .keyboard(.init(key: key, modifiers: modifiers, targetBundleID: target.isEmpty ? nil : target))
            case .website: .website(url: website)
            case .shortcut: .shortcut(identifier: shortcut)
            case .wait: .wait(seconds: seconds)
            }
            do { try step.validate(); save(step); model.feedback(.selection); dismiss() } catch { self.error = error.localizedDescription }
        } } }
        .onAppear {
            guard let existing else { return }
            switch existing {
            case .launchApp(let id): kind = .app; target = id
            case .keyboard(let value): kind = .keyboard; target = value.targetBundleID ?? ""; key = value.key; modifiers = value.modifiers
            case .website(let url): kind = .website; website = url
            case .shortcut(let id): kind = .shortcut; shortcut = id
            case .wait(let value): kind = .wait; seconds = value
            }
        }
    }
}
