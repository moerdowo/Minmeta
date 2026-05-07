import SwiftUI
import AppKit

/// Reusable Winamp-style panel: gradient title bar with control dots and a
/// content area beneath. The first panel in the window is the "main" panel
/// whose dots actually drive the host window; the rest are decorative.
struct WinampPanel<Content: View>: View {
    let title: String
    let isMain: Bool
    let trailing: AnyView?
    let content: () -> Content

    init(title: String,
         isMain: Bool = false,
         trailing: AnyView? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.isMain = isMain
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelTitleBar(title: title, isMain: isMain, trailing: trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(WinampTheme.panelGradient)
        }
        .background(WinampTheme.panelGradient)
        .bevelOut()
    }
}

private struct PanelTitleBar: View {
    let title: String
    let isMain: Bool
    let trailing: AnyView?

    var body: some View {
        ZStack {
            WinampTheme.titleGradient
            HStack(spacing: 6) {
                Text(title)
                    .font(WinampTheme.titleFont)
                    .foregroundColor(WinampTheme.titleText)
                    .shadow(color: .black.opacity(0.7), radius: 1, x: 0, y: 1)
                    .padding(.leading, 8)
                Spacer()
                if let trailing = trailing {
                    trailing.padding(.trailing, 6)
                }
                if isMain {
                    WindowControlButton(symbol: "minus") {
                        NSApp.keyWindow?.performMiniaturize(nil)
                    }
                    WindowControlButton(symbol: "square") {
                        NSApp.keyWindow?.performZoom(nil)
                    }
                    WindowControlButton(symbol: "xmark") {
                        NSApp.keyWindow?.performClose(nil)
                    }
                    .padding(.trailing, 4)
                } else {
                    Spacer().frame(width: 4)
                }
            }
        }
        .frame(height: 20)
        .bevelOut()
        .gesture(
            // Allow dragging the window from any panel title bar.
            DragGesture(minimumDistance: 4).onChanged { _ in
                if let evt = NSApp.currentEvent {
                    NSApp.keyWindow?.performDrag(with: evt)
                }
            }
        )
    }
}

private struct WindowControlButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(hovered ? WinampTheme.titleText : WinampTheme.titleTextDim)
                .frame(width: 16, height: 14)
                .background(WinampTheme.titleBar1)
                .overlay(Rectangle().strokeBorder(WinampTheme.titleText.opacity(0.5),
                                                  lineWidth: hovered ? 1 : 0.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
