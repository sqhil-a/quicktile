import SwiftUI
import PhotosUI

struct IconSettingsView: View {
    @Binding var symbol: String
    @Binding var reference: String?
    var website = false
    @EnvironmentObject private var model: PhoneModel
    @State private var selection: PhotosPickerItem?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    Group {
                        if let reference { RemoteIcon(source: .custom(reference), store: model.images, fallback: symbol) }
                        else { Image(systemName: symbol).resizable().scaledToFit().padding(12) }
                    }.frame(width: 80, height: 80)
                    Spacer()
                }.padding(.vertical, 12)
            }
            Section {
                if website { Button("Use website icon", systemImage: "globe") { reference = nil; symbol = "globe"; model.feedback(.selection) } }
                NavigationLink { Form { IconChooser(selection: Binding(get: { symbol }, set: { symbol = $0; reference = nil })) }.navigationTitle("Symbol") } label: { Label("Choose symbol", systemImage: "square.grid.3x3") }
                PhotosPicker(selection: $selection, matching: .images) { Label(loading ? "Preparing image…" : "Choose image", systemImage: "photo") }.disabled(loading)
                if reference != nil { Button("Remove image", role: .destructive) { reference = nil } }
                if let error { Text(error).foregroundStyle(.red) }
            }
        }.navigationTitle("Icon").navigationBarTitleDisplayMode(.inline)
        .onChange(of: selection) { _, value in
            guard let value else { return }
            Task {
                loading = true; defer { loading = false }
                do {
                    guard let data = try await value.loadTransferable(type: Data.self) else { return }
                    reference = try await model.images.importCustomImage(data); model.feedback(.selection)
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}
