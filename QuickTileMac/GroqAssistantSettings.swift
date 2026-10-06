import SwiftUI

struct GroqAssistantSettings: View {
    @ObservedObject var store: GroqAssistant
    @State private var key = ""
    @State private var error: String?
    var body: some View {
        LabeledContent("Groq", value: store.configured ? "Configured" : "Not configured")
        if !store.configured, store.status != "Not configured" { Text(store.status).font(.caption).foregroundStyle(.secondary) }
        SecureField(store.configured ? "Replace API key" : "Groq API key", text: $key)
            .textContentType(.password)
        HStack {
            Button("Save key") {
                do { try store.saveKey(key); key = ""; error = nil } catch { self.error = error.localizedDescription }
            }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if store.configured {
                Button("Remove key", role: .destructive) {
                    do { try store.removeKey(); key = ""; error = nil } catch { self.error = error.localizedDescription }
                }
            }
        }
        Text("Your key stays in this Mac’s Keychain. Voice audio stays on your iPhone. Commands and available app and Shortcut names are sent to Groq for interpretation. Groq usage may incur charges on your account.")
            .font(.caption).foregroundStyle(.secondary)
        Link("Groq data policy", destination: URL(string: "https://console.groq.com/docs/your-data")!)
        if let error { Text(error).font(.caption).foregroundStyle(.red) }
    }
}
