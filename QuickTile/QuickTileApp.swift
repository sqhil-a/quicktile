import SwiftUI
import UIKit
import QuickTileCore

@main
struct QuickTileApp: App {
    @StateObject private var model = PhoneModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
                .tint(.primary)
                .preferredColorScheme(model.layout?.settings.theme == .dark ? .dark : model.layout?.settings.theme == .light ? .light : nil)
                .onChange(of: phase, initial: true) { _, value in model.setForeground(value == .active) }
        }
    }
}
