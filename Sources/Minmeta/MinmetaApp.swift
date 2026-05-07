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
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if state.isUnlocked {
                MainScreenView()
                    .frame(width: 560, height: 620)
            } else {
                LockScreenView()
                    .frame(width: 560, height: 320)
            }
        }
        .padding(8)
        .background(WinampTheme.windowBg)
    }
}
