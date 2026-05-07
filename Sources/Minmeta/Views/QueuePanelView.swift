import SwiftUI

/// Bottom "MINMETA QUEUE" panel — Winamp playlist styling. Each row shows the
/// filename, the latest status, the resolved metadata once known, and a
/// per-row spinner / progress bar / elapsed counter for in-flight items.
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
        // One TimelineView at the list level drives every row's elapsed
        // counter and LED pulse off the same clock — cheaper than putting a
        // timer inside each row, and keeps animations in lockstep.
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if state.queue.isEmpty {
                        EmptyHint()
                    } else {
                        ForEach(Array(state.queue.enumerated()), id: \.element.id) {
                            idx, item in
                            QueueRow(index: idx + 1, item: item, now: ctx.date)
                                .background(idx.isMultiple(of: 2)
                                            ? Color.clear
                                            : WinampTheme.lcdBg.opacity(0.35))
                        }
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
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 8) {
                LEDIndicator(item: item, now: now)
                    .padding(.top, 3)

                Text(String(format: "%2d.", index))
                    .font(WinampTheme.lcdFont)
                    .foregroundColor(badgeColor)
                    .frame(width: 24, alignment: .trailing)

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

                if item.status == .processing {
                    PhaseChip(phase: item.phase)
                    ElapsedReadout(start: item.startedAt, now: now)
                }

                StatusBadge(status: item.status)
            }
            .padding(.horizontal, 10).padding(.top, 4)

            // Per-row progress bar — only when processing. Shows phase
            // fraction (READ 25 · AI 65 · TAG 90) plus a live shimmer so it
            // doesn't look frozen during the long AI step.
            if item.status == .processing {
                RowProgressBar(phase: item.phase, now: now)
                    .padding(.horizontal, 10).padding(.bottom, 4)
            } else {
                Color.clear.frame(height: 4)
            }
        }
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
        case .processing: return WinampTheme.lcdAmber.opacity(0.95)
        case .skipped:    return WinampTheme.lcdGreenDim
        default:          return WinampTheme.lcdGreenDim
        }
    }
}

// MARK: - LED indicator (animated)

private struct LEDIndicator: View {
    let item: QueueItem
    let now: Date

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: glowColor.opacity(0.7), radius: 3)
            .overlay(
                Circle()
                    .strokeBorder(Color.black.opacity(0.6), lineWidth: 0.5)
            )
            .opacity(opacity)
    }

    private var color: Color {
        switch item.status {
        case .processing:
            switch item.phase {
            case .reading: return WinampTheme.lcdGreen
            case .asking:  return WinampTheme.lcdCyan
            case .writing: return WinampTheme.lcdAmber
            default:       return WinampTheme.lcdGreenDim
            }
        case .done:    return WinampTheme.lcdGreen
        case .failed:  return WinampTheme.lcdRed
        case .skipped: return WinampTheme.lcdGreenDim
        case .pending: return WinampTheme.lcdGreenDim.opacity(0.4)
        }
    }

    private var glowColor: Color { color }

    private var opacity: Double {
        guard item.status == .processing else { return 1.0 }
        // 1 Hz pulse via the shared TimelineView clock.
        let t = now.timeIntervalSinceReferenceDate
        return 0.55 + 0.45 * (sin(t * 6.28) * 0.5 + 0.5)
    }
}

// MARK: - Phase chip

private struct PhaseChip: View {
    let phase: QueueItem.Phase
    var body: some View {
        Text(phase.label)
            .font(WinampTheme.smallFont)
            .foregroundColor(color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(WinampTheme.lcdBg)
            .bevelIn()
    }
    private var color: Color {
        switch phase {
        case .waiting:  return WinampTheme.lcdGreenDim
        case .reading:  return WinampTheme.lcdGreen
        case .asking:   return WinampTheme.lcdCyan
        case .writing:  return WinampTheme.lcdAmber
        case .finished: return WinampTheme.lcdGreen
        case .errored:  return WinampTheme.lcdRed
        }
    }
}

// MARK: - Elapsed readout (live)

private struct ElapsedReadout: View {
    let start: Date?
    let now: Date

    var body: some View {
        Text(formatted)
            .font(WinampTheme.smallFont)
            .foregroundColor(WinampTheme.lcdAmber)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(WinampTheme.lcdBg)
            .bevelIn()
            .frame(width: 50)
    }

    private var formatted: String {
        guard let start = start else { return "—" }
        let secs = max(0, now.timeIntervalSince(start))
        if secs < 10 { return String(format: "%.1fS", secs) }
        if secs < 60 { return String(format: "%.0fS", secs) }
        let m = Int(secs) / 60
        let s = Int(secs) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Per-row progress bar

private struct RowProgressBar: View {
    let phase: QueueItem.Phase
    let now: Date

    var body: some View {
        GeometryReader { geo in
            let frac = phase.fraction
            ZStack(alignment: .leading) {
                Rectangle().fill(WinampTheme.lcdBg)
                Rectangle()
                    .fill(LinearGradient(colors: [WinampTheme.lcdGreenDim,
                                                  fillTip],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * frac)
                // A thin shimmer that travels across the filled portion so
                // long-running phases (the AI call) don't look frozen.
                if phase == .asking || phase == .reading {
                    let t = now.timeIntervalSinceReferenceDate
                    let shimmerX = (sin(t * 1.6) * 0.5 + 0.5) * (geo.size.width * frac)
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 14)
                        .offset(x: shimmerX - 7)
                        .clipped()
                }
            }
            .bevelIn()
        }
        .frame(height: 4)
    }

    private var fillTip: Color {
        switch phase {
        case .reading: return WinampTheme.lcdGreen
        case .asking:  return WinampTheme.lcdCyan
        case .writing: return WinampTheme.lcdAmber
        default:       return WinampTheme.lcdGreen
        }
    }
}

// MARK: - Status badge

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

// MARK: - Footer

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
