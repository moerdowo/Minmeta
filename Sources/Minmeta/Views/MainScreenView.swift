import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Post-unlock layout: MAIN panel with drop zone + status, then QUEUE panel
/// underneath. The CFG button in the main panel's title bar opens the
/// settings window (declared as a separate Window scene in MinmetaApp).
struct MainScreenView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 8) {
            MainPanelView()
            QueuePanelView()
        }
    }
}

// MARK: - Main panel (drop zone + status)

private struct MainPanelView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        WinampPanel(
            title: "M I N M E T A",
            isMain: true,
            trailing: AnyView(
                HStack(spacing: 4) {
                    SmallTitleButton(label: "CFG") {
                        openWindow(id: "settings")
                    }
                }
            )
        ) {
            VStack(spacing: 8) {
                StatusReadout()
                DropZone()
                ActivityRow()
            }
            .padding(10)
        }
    }
}

private struct SmallTitleButton: View {
    let label: String
    var active: Bool = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(WinampTheme.smallFont)
                .foregroundColor(active ? WinampTheme.lcdAmber
                                        : (hovered ? WinampTheme.titleText
                                                   : WinampTheme.titleTextDim))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(active ? WinampTheme.lcdBg : WinampTheme.titleBar1)
                .overlay(Rectangle()
                    .strokeBorder(WinampTheme.titleText.opacity(0.4), lineWidth: 0.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Status

private struct StatusReadout: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                LCDDisplay {
                    HStack(spacing: 4) {
                        Image(systemName: state.isProcessing ? "waveform" : "pause.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(state.isProcessing
                                ? WinampTheme.lcdAmber : WinampTheme.lcdGreenDim)
                        Text(progressString)
                            .font(WinampTheme.lcdBigFont)
                            .foregroundColor(state.isProcessing
                                ? WinampTheme.lcdAmber : WinampTheme.lcdGreen)
                    }
                }
                HStack(spacing: 4) {
                    PillBadge(text: "READY",
                              on: !state.isProcessing)
                    PillBadge(text: "WORK",
                              on: state.isProcessing,
                              activeColor: WinampTheme.lcdAmber)
                }
            }
            .frame(width: 170)

            LCDDisplay {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.statusMessage.uppercased())
                        .font(WinampTheme.lcdFont)
                        .foregroundColor(state.isProcessing
                            ? WinampTheme.lcdAmber : WinampTheme.lcdGreen)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 8) {
                        Text("ITUNES")
                            .font(WinampTheme.smallFont)
                            .foregroundColor(WinampTheme.lcdGreen)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(WinampTheme.lcdBg)
                            .bevelIn()

                        Text(state.aiEnabled ? "AI: " + state.model.uppercased()
                                             : "AI: OFF")
                            .font(WinampTheme.smallFont)
                            .foregroundColor(state.aiEnabled
                                ? WinampTheme.lcdCyan : WinampTheme.lcdGreenDim)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(WinampTheme.lcdBg)
                            .bevelIn()

                        Spacer()
                        Text(state.aiEnabled ? "FALLBACK READY" : "ITUNES-ONLY")
                            .font(WinampTheme.smallFont)
                            .foregroundColor(WinampTheme.lcdGreenDim)
                    }
                }
            }
        }
    }

    private var progressString: String {
        let done = state.queue.filter {
            $0.status == .done || $0.status == .skipped
        }.count
        let total = state.queue.count
        if total == 0 { return "0:00" }
        return String(format: "%02d/%02d", done, total)
    }
}

// MARK: - Drop zone

private struct DropZone: View {
    @EnvironmentObject var state: AppState
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            Rectangle().fill(WinampTheme.lcdBg).bevelIn()
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(isTargeted
                        ? WinampTheme.lcdAmber : WinampTheme.lcdGreen)

                Text(isTargeted
                     ? "RELEASE TO ENQUEUE"
                     : "DROP FILES OR FOLDER HERE")
                    .font(WinampTheme.bigFont)
                    .foregroundColor(isTargeted
                        ? WinampTheme.lcdAmber : WinampTheme.lcdGreen)

                Text("MP3 · M4A · FLAC · WAV · AIFF · OGG")
                    .font(WinampTheme.smallFont)
                    .foregroundColor(WinampTheme.lcdGreenDim)

                WinampButton(title: "BROWSE…", width: 110) { browse() }
                    .padding(.top, 4)
            }
            .padding(14)
        }
        .overlay(
            Rectangle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundColor(isTargeted
                    ? WinampTheme.lcdAmber
                    : WinampTheme.lcdGreenDim.opacity(0.6))
                .padding(4)
        )
        .frame(minHeight: 130)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { obj, _ in
                if let url = obj { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { state.enqueue(urls: urls) }
        }
        return true
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio,
                                     .wav, .aiff, .folder]
        panel.message = "Select audio files or folders"
        if panel.runModal() == .OK { state.enqueue(urls: panel.urls) }
    }
}

// MARK: - Activity row (meter + progress)

private struct ActivityRow: View {
    @EnvironmentObject var state: AppState
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 8) {
            ActivityMeter(active: state.isProcessing, phase: phase)
                .frame(width: 180, height: 22)
            ProgressTrack()
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
                phase = (phase &+ 1) & 0xFF
            }
        }
    }
}

private struct ActivityMeter: View {
    let active: Bool
    let phase: Int

    var body: some View {
        GeometryReader { geo in
            let bars = 18
            let gap: CGFloat = 2
            let w = (geo.size.width - CGFloat(bars - 1) * gap) / CGFloat(bars)
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(0..<bars, id: \.self) { i in
                    let h = barHeight(i: i, full: geo.size.height - 4)
                    Rectangle()
                        .fill(barColor(h: h, full: geo.size.height - 4))
                        .frame(width: w, height: h)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(2)
            .background(WinampTheme.lcdBg)
            .bevelIn()
        }
    }

    private func barHeight(i: Int, full: CGFloat) -> CGFloat {
        if !active { return full * 0.18 }
        let s = sin(Double(i + phase) * 0.8) * 0.5 + 0.5
        let t = sin(Double(phase) * 0.3 + Double(i)) * 0.5 + 0.5
        return CGFloat(0.25 + 0.7 * s * t) * full
    }

    private func barColor(h: CGFloat, full: CGFloat) -> Color {
        let r = h / max(full, 1)
        if r > 0.8  { return WinampTheme.lcdRed }
        if r > 0.55 { return WinampTheme.lcdAmber }
        return WinampTheme.lcdGreen
    }
}

private struct ProgressTrack: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        GeometryReader { geo in
            let frac = progressFraction
            ZStack(alignment: .leading) {
                Rectangle().fill(WinampTheme.lcdBg)
                Rectangle()
                    .fill(LinearGradient(colors: [WinampTheme.lcdGreenDim,
                                                  WinampTheme.lcdGreen],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * frac)
                Rectangle()
                    .fill(WinampTheme.lcdYellow)
                    .frame(width: 6, height: geo.size.height - 4)
                    .offset(x: max(0, geo.size.width * frac - 3), y: 0)
            }
            .bevelIn()
        }
        .frame(height: 22)
    }

    private var progressFraction: CGFloat {
        let total = state.queue.count
        guard total > 0 else { return 0 }
        let done = state.queue.filter {
            $0.status == .done || $0.status == .skipped
        }.count
        return CGFloat(done) / CGFloat(total)
    }
}
