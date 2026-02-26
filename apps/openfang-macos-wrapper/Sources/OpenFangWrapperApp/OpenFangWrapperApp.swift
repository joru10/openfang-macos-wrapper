import SwiftUI

@main
struct OpenFangWrapperApp: App {
    @NSApplicationDelegateAdaptor(WrapperAppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(state)
                .frame(minWidth: 900, minHeight: 620)
                .onAppear {
                    AppBridge.state = state
                }
        }

        Settings {
            SettingsView()
                .environmentObject(state)
                .frame(width: 760, height: 560)
        }
    }
}
