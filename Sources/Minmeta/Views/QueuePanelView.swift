import SwiftUI

/// Bottom "MINMETA QUEUE" panel — Winamp playlist styling. Each row shows the
/// filename, the latest status, the resolved metadata once known, and a
/// per-row spinner / colour for in-flight items.
struct QueuePanelView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        WinampPanel(title: "M I N M E T A · Q U E U E") {
            VStack(spacing: 6) {
                QueueList()
                QueueFooter()
            }
            .padding(8)
        }
    }
}

private struct QueueList: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if state.queue.isEmpty {
                    EmptyHint()
                } else {
                    ForEach(Array(state.queue.enumerated()), id: \.element.id) {
                        idx, item in
                        QueueRow(index: idx + 1, item: item)
                            .background(idx.isMultiple(of: 2)
                                        ? Color.clear
                                        : WinampTheme.lcdBg.opacity(0.35))
                    }
                }
            }
        }
        .frame(minHeight: 220, maxHeight: .infinity)
        .background(WinampTheme.lcdBg)
        .bevelIn()
    }
}

private struct EmptyHint: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("— QUEUE EMPTY —")
                .font(WinampTheme.pixelFont)
                .foregroundColor(WinampTheme.lcdGreenDim)
            Text("DROP FILES OR FOLDERS INTO THE PANEL ABOVE")
                .font(WinampTheme.smallFont)
                .foregroundColor(WinampTheme.lcdGreenDim.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

private struct QueueRow: View {
    let index: Int
    let item: QueueItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(String(format: "%2d.", index))
                .font(WinampTheme.lcdFont)
                .foregroundColor(badgeColor)
                .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent)
                    .font(WinampTheme.lcdFont)
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(WinampTheme.smallFont)
                        .foregroundColor(detailColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)

            StatusBadge(status: item.status)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
    }

    private var textColor: Color {
        switch item.status {
        case .processing: return WinampTheme.lcdAmber
        case .failed:     return WinampTheme.lcdRed
        case .done:       return WinampTheme.lcdYellow
        case .skipped:    return WinampTheme.lcdGreenDim
        case .pending:    return WinampTheme.lcdGreen
        }
    }
    private var badgeColor: Color {
        switch item.status {
        case .processing: return WinampTheme.lcdAmber
        case .failed:     return WinampTheme.lcdRed
        case .done:       return WinampTheme.lcdGreen
        case .skipped:    return WinampTheme.lcdGreenDim
        case .pending:    return WinampTheme.lcdGreenDim
        }
    }
    private var detailColor: Color {
        switch item.status {
        case .failed:     return WinampTheme.lcdRed.opacity(0.85)
        case .done:       return WinampTheme.lcdGreen
        case .processing: return WinampTheme.lcdAmber.opacity(0.85)
        default:          return WinampTheme.lcdGreenDim
        }
    }
}

private struct StatusBadge: View {
    let status: QueueItem.Status
    var body: some View {
        Text(status.rawValue)
            .font(WinampTheme.smallFont)
            .foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(WinampTheme.lcdBg)
            .bevelIn()
    }
    private var color: Color {
        switch status {
        case .processing: return WinampTheme.lcdAmber
        case .failed:     return WinampTheme.lcdRed
        case .done:       return WinampTheme.lcdGreen
        case .skipped:    return WinampTheme.lcdGreenDim
        case .pending:    return WinampTheme.lcdGreenDim
        }
    }
}

private struct QueueFooter: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            WinampButton(title: "CLEAR", width: 64) {
                state.clearQueue()
            }
            WinampButton(title: "REMOVE DONE", width: 110) {
                state.queue.removeAll {
                    $0.status == .done || $0.status == .skipped
                }
            }
            WinampButton(title: "RETRY FAILED", width: 110,
                         color: WinampTheme.lcdAmber) {
                state.retryFailed()
            }
            Spacer()
            CounterReadout(label: "TOTAL",
                           value: "\(state.queue.count)")
            CounterReadout(label: "DONE",
                           value: "\(state.queue.filter { $0.status == .done }.count)",
                           color: WinampTheme.lcdGreen)
            CounterReadout(label: "WORK",
                           value: "\(state.queue.filter { $0.status == .processing }.count)",
                           color: WinampTheme.lcdAmber)
            CounterReadout(label: "FAIL",
                           value: "\(state.queue.filter { $0.status == .failed }.count)",
                           color: WinampTheme.lcdRed)
        }
    }
}

private struct CounterReadout: View {
    let label: String
    let value: String
    var color: Color = WinampTheme.lcdAmber
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(WinampTheme.smallFont)
                .foregroundColor(WinampTheme.lcdGreenDim)
            Text(value)
                .font(WinampTheme.lcdFont)
                .foregroundColor(color)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(WinampTheme.lcdBg)
                .bevelIn()
        }
    }
}
