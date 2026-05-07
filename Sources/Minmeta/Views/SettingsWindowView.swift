import SwiftUI
import AppKit

/// The standalone settings window opened from the main panel's CFG button.
/// Edits stay local until the user clicks SAVE; CANCEL or the title-bar
/// close discard them.
struct SettingsWindowView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var key: String = ""
    @State private var baseURL: String = ""
    @State private var model: String = ""
    @State private var note: String? = nil
    @State private var ready: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            WinampPanel(title: "M I N M E T A · S E T T I N G S", isMain: true) {
                VStack(alignment: .leading, spacing: 10) {
                    FieldRow(label: "API KEY (LEAVE BLANK TO KEEP CURRENT)",
                             placeholder: "sk-...",
                             secure: true,
                             text: $key,
                             onSubmit: save)

                    HStack(spacing: 8) {
                        FieldRow(label: "BASE URL",
                                 placeholder: "https://api.openai.com/v1",
                                 secure: false,
                                 text: $baseURL,
                                 onSubmit: save)
                        FieldRow(label: "MODEL",
                                 placeholder: "gpt-4o-mini",
                                 secure: false,
                                 text: $model,
                                 onSubmit: save,
                                 width: 180)
                    }

                    HStack {
                        if let note = note {
                            Text(note.uppercased())
                                .font(WinampTheme.smallFont)
                                .foregroundColor(WinampTheme.lcdGreen)
                        } else {
                            Text("◆ KEY ON FILE — \(state.apiKey.count) CHARS")
                                .font(WinampTheme.smallFont)
                                .foregroundColor(WinampTheme.lcdGreen)
                        }
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        WinampButton(title: "FORGET KEY", width: 110,
                                     color: WinampTheme.lcdRed) {
                            state.clearAPIKey()
                            note = "key cleared"
                        }
                        Spacer()
                        WinampButton(title: "CANCEL", width: 90,
                                     color: WinampTheme.lcdGreenDim) {
                            dismissWindow()
                        }
                        WinampButton(title: "SAVE", width: 90,
                                     color: WinampTheme.lcdAmber, action: save)
                    }
                    .padding(.top, 4)
                }
                .padding(12)
            }
        }
        .padding(8)
        .background(WinampTheme.windowBg)
        .frame(width: 540, height: 280)
        .onAppear {
            // Pull current values once. Subsequent re-opens (the Window scene
            // is single-instance) keep edits if the user dismissed without
            // saving — that's by design and matches macOS's Sheets/Inspector
            // behaviour. Reset on first appear by checking `ready`.
            if !ready {
                baseURL = state.baseURL
                model = state.model
                ready = true
            }
        }
    }

    private func save() {
        let trimmedKey   = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBase  = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveKey = trimmedKey.isEmpty ? state.apiKey : trimmedKey

        guard !effectiveKey.isEmpty else {
            note = "no key set — paste one above"
            return
        }

        state.saveAPIKey(effectiveKey,
                         baseURL: trimmedBase,
                         model: trimmedModel)
        key = ""
        dismissWindow()
    }
}
