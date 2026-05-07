import SwiftUI

/// Pre-unlock screen — single Winamp panel asking for the API key, base URL,
/// and model. Once an API key is saved the app rebuilds itself into the main
/// drop-zone-and-queue layout.
struct LockScreenView: View {
    @EnvironmentObject var state: AppState

    @State private var key: String = ""
    @State private var baseURL: String = ""
    @State private var model: String = ""
    @State private var isVerifying = false
    @State private var errorText: String? = nil

    var body: some View {
        WinampPanel(title: "M I N M E T A · A P I   K E Y", isMain: true) {
            VStack(spacing: 10) {
                BannerLCD()

                FieldRow(label: "OPENAI API KEY",
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

                if let err = errorText {
                    HStack(spacing: 6) {
                        Text("◆")
                            .font(WinampTheme.pixelFont)
                            .foregroundColor(WinampTheme.lcdRed)
                        Text(err.uppercased())
                            .font(WinampTheme.pixelFont)
                            .foregroundColor(WinampTheme.lcdRed)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    Text("◆ KEY IS STORED IN MACOS KEYCHAIN")
                        .font(WinampTheme.smallFont)
                        .foregroundColor(WinampTheme.lcdGreenDim)
                    Spacer()
                    if isVerifying {
                        Text("VERIFYING…")
                            .font(WinampTheme.pixelFont)
                            .foregroundColor(WinampTheme.lcdAmber)
                    }
                    WinampButton(title: isVerifying ? "WAIT…" : "UNLOCK  ▶",
                                 width: 130,
                                 color: isVerifying
                                    ? WinampTheme.lcdGreenDim : WinampTheme.lcdAmber,
                                 disabled: isVerifying,
                                 action: save)
                }
            }
            .padding(12)
        }
        .onAppear {
            baseURL = state.baseURL
            model = state.model
        }
    }

    private func save() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorText = "API key cannot be empty"
            return
        }
        let trimmedBase  = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        let effectiveBase  = trimmedBase.isEmpty  ? "https://api.openai.com/v1" : trimmedBase
        let effectiveModel = trimmedModel.isEmpty ? "gpt-4o-mini"               : trimmedModel

        errorText = nil
        isVerifying = true

        Task {
            let client = OpenAIClient(apiKey: trimmed,
                                      baseURL: effectiveBase,
                                      model: effectiveModel)
            let problem = await client.verify()
            await MainActor.run {
                isVerifying = false
                if let problem = problem {
                    errorText = problem
                    return
                }
                state.saveAPIKey(trimmed,
                                 baseURL: effectiveBase,
                                 model: effectiveModel)
                key = ""
            }
        }
    }
}

private struct BannerLCD: View {
    var body: some View {
        LCDDisplay(padH: 12, padV: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(WinampTheme.lcdGreen)
                    Text("MINMETA · METADATA COMPLETER")
                        .font(WinampTheme.bigFont)
                        .foregroundColor(WinampTheme.lcdGreen)
                }
                Text("ENTER OPENAI-COMPATIBLE API KEY TO UNLOCK.")
                    .font(WinampTheme.pixelFont)
                    .foregroundColor(WinampTheme.lcdGreenDim)
                Text("YOUR KEY IS STORED LOCALLY · IT NEVER LEAVES THIS MAC EXCEPT TO THE BASE URL YOU SET.")
                    .font(WinampTheme.smallFont)
                    .foregroundColor(WinampTheme.lcdGreenDim.opacity(0.85))
            }
        }
    }
}

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
