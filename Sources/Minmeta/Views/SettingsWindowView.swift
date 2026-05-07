import SwiftUI
import AppKit

/// The standalone settings window opened from the main panel's CFG button.
/// Edits stay local until the user clicks SAVE; CANCEL or the title-bar
/// close discard them.
///
/// The API key is **optional** — Minmeta works iTunes-only without one.
/// When set, the model is used as a fallback for filenames iTunes can't
/// identify (messy names, bootlegs, very obscure indie). See README.
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
                    HelpHeader(aiEnabled: state.aiEnabled)

                    FieldRow(label: "OPENAI-COMPATIBLE API KEY · OPTIONAL · LEAVE BLANK FOR ITUNES-ONLY",
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
                        } else if state.aiEnabled {
                            Text("◆ AI FALLBACK ENABLED — KEY ON FILE (\(state.apiKey.count) CHARS)")
                                .font(WinampTheme.smallFont)
                                .foregroundColor(WinampTheme.lcdGreen)
                        } else {
                            Text("◆ ITUNES-ONLY MODE — NO AI FALLBACK")
                                .font(WinampTheme.smallFont)
                                .foregroundColor(WinampTheme.lcdGreenDim)
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
        .frame(width: 560, height: 320)
        .onAppear {
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

        state.saveAPIKey(effectiveKey,
                         baseURL: trimmedBase,
                         model: trimmedModel)
        key = ""
        dismissWindow()
    }
}

private struct HelpHeader: View {
    let aiEnabled: Bool
    var body: some View {
        LCDDisplay(padH: 10, padV: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ITUNES IS THE PRIMARY METADATA SOURCE.")
                    .font(WinampTheme.pixelFont)
                    .foregroundColor(WinampTheme.lcdGreen)
                Text("OPTIONAL: ADD AN OPENAI-COMPATIBLE KEY BELOW TO LET MINMETA FALL BACK TO AI WHEN ITUNES CAN'T IDENTIFY A TRACK (MESSY FILENAMES, BOOTLEGS, OBSCURE INDIE).")
                    .font(WinampTheme.smallFont)
                    .foregroundColor(WinampTheme.lcdGreenDim)
                    .lineLimit(3)
            }
        }
    }
}

// MARK: - Shared field row

struct FieldRow: View {
    let label: String
    let placeholder: String
    let secure: Bool
    @Binding var text: String
    let onSubmit: () -> Void
    var width: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(WinampTheme.smallFont)
                .foregroundColor(WinampTheme.lcdGreenDim)
                .lineLimit(1)
                .truncationMode(.tail)
            Group {
                if secure {
                    SecureField("", text: $text,
                                prompt: Text(placeholder)
                                    .foregroundColor(WinampTheme.lcdGreenDim.opacity(0.7)))
                        .onSubmit(onSubmit)
                } else {
                    TextField("", text: $text,
                              prompt: Text(placeholder)
                                  .foregroundColor(WinampTheme.lcdGreenDim.opacity(0.7)))
                        .onSubmit(onSubmit)
                }
            }
            .textFieldStyle(.plain)
            .font(WinampTheme.lcdFont)
            .foregroundColor(WinampTheme.lcdGreen)
            .padding(.horizontal, 6).padding(.vertical, 5)
            .background(WinampTheme.lcdBg)
            .bevelIn()
        }
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}
