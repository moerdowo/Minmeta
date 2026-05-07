import SwiftUI
import AppKit

@main
struct MinmetaApp: App {
    @StateObject private var appState = AppState()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Minmeta") {
            RootView()
                .environmentObject(appState)
                .background(WinampTheme.bgGradient)
                .preferredColorScheme(.dark)
                .focusEffectDisabled()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Settings as its own window. CFG button in the main panel opens
        // it via `openWindow(id: "settings")`; the window's own Cancel /
        // Save / red-traffic-light close are all the documented exits.
        Window("Minmeta · Settings", id: "settings") {
            SettingsWindowView()
                .environmentObject(appState)
                .background(WinampTheme.bgGradient)
                .preferredColorScheme(.dark)
                .focusEffectDisabled()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        MainScreenView()
            .frame(width: 560, height: 620)
            .padding(8)
            .background(WinampTheme.windowBg)
    }
}
