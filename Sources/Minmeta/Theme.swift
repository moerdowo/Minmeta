import SwiftUI

enum WinampTheme {
    // Window / panels
    static let windowBg     = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let panel        = Color(red: 0.21, green: 0.22, blue: 0.25)
    static let panelInner   = Color(red: 0.16, green: 0.17, blue: 0.20)
    static let panelDeep    = Color(red: 0.10, green: 0.11, blue: 0.13)

    static let bevelLight   = Color(red: 0.55, green: 0.55, blue: 0.60)
    static let bevelMid     = Color(red: 0.30, green: 0.30, blue: 0.35)
    static let bevelDark    = Color(red: 0.04, green: 0.04, blue: 0.06)

    // Title bar — matches the cyan-on-blue gradient in the mockup
    static let titleBar1    = Color(red: 0.10, green: 0.18, blue: 0.34)
    static let titleBar2    = Color(red: 0.20, green: 0.32, blue: 0.55)
    static let titleText    = Color(red: 0.62, green: 0.82, blue: 1.00)
    static let titleTextDim = Color(red: 0.32, green: 0.45, blue: 0.65)

    // LCD displays
    static let lcdBg        = Color(red: 0.02, green: 0.03, blue: 0.04)
    static let lcdGreen     = Color(red: 0.40, green: 1.00, blue: 0.50)
    static let lcdGreenDim  = Color(red: 0.18, green: 0.55, blue: 0.25)
    static let lcdAmber     = Color(red: 1.00, green: 0.78, blue: 0.20)
    static let lcdAmberDim  = Color(red: 0.55, green: 0.42, blue: 0.10)
    static let lcdRed       = Color(red: 1.00, green: 0.40, blue: 0.40)
    static let lcdCyan      = Color(red: 0.55, green: 0.90, blue: 1.00)
    static let lcdYellow    = Color(red: 0.95, green: 0.85, blue: 0.30)

    // Buttons
    static let btnFace      = Color(red: 0.30, green: 0.31, blue: 0.34)
    static let btnFaceLight = Color(red: 0.40, green: 0.41, blue: 0.45)

    // Knob / slider yellow (like EQ sliders in the mockup)
    static let knobYellow   = Color(red: 0.93, green: 0.83, blue: 0.20)
    static let knobShadow   = Color(red: 0.48, green: 0.42, blue: 0.05)

    // Backgrounds
    static let bgGradient = LinearGradient(
        colors: [Color(red: 0.10, green: 0.10, blue: 0.13),
                 Color(red: 0.05, green: 0.05, blue: 0.07)],
        startPoint: .top, endPoint: .bottom
    )

    static let titleGradient = LinearGradient(
        colors: [titleBar2, titleBar1],
        startPoint: .top, endPoint: .bottom
    )

    static let panelGradient = LinearGradient(
        colors: [Color(red: 0.24, green: 0.25, blue: 0.28),
                 Color(red: 0.18, green: 0.19, blue: 0.22)],
        startPoint: .top, endPoint: .bottom
    )

    // Fonts — monospaced gives the LCD/pixel feel without needing custom font files
    static let pixelFont   = Font.system(size: 10, weight: .bold,     design: .monospaced)
    static let smallFont   = Font.system(size: 9,  weight: .semibold, design: .monospaced)
    static let lcdFont     = Font.system(size: 12, weight: .semibold, design: .monospaced)
    static let titleFont   = Font.system(size: 10, weight: .heavy,    design: .monospaced)
    static let bigFont     = Font.system(size: 16, weight: .bold,     design: .monospaced)
    static let lcdBigFont  = Font.system(size: 24, weight: .heavy,    design: .monospaced)
    static let lcdHugeFont = Font.system(size: 30, weight: .black,    design: .monospaced)
}

// MARK: - Bevel modifiers

struct BevelOut: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(
                Rectangle()
                    .strokeBorder(LinearGradient(
                        colors: [WinampTheme.bevelLight, WinampTheme.bevelDark],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                                  lineWidth: 1)
            )
    }
}

struct BevelIn: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(
                Rectangle()
                    .strokeBorder(LinearGradient(
                        colors: [WinampTheme.bevelDark, WinampTheme.bevelLight],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                                  lineWidth: 1)
            )
    }
}

extension View {
    func bevelOut() -> some View { modifier(BevelOut()) }
    func bevelIn()  -> some View { modifier(BevelIn()) }
}

// MARK: - LCD container

struct LCDDisplay<Content: View>: View {
    let content: () -> Content
    var padH: CGFloat = 8
    var padV: CGFloat = 6

    init(padH: CGFloat = 8, padV: CGFloat = 6,
         @ViewBuilder content: @escaping () -> Content) {
        self.padH = padH
        self.padV = padV
        self.content = content
    }

    var body: some View {
        content()
            .padding(.horizontal, padH)
            .padding(.vertical, padV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WinampTheme.lcdBg)
            .bevelIn()
    }
}

// MARK: - Winamp button

struct WinampButton: View {
    let title: String
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    var color: Color = WinampTheme.lcdGreen
    var disabled: Bool = false
    var action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: { if !disabled { action() } }) {
            Text(title)
                .font(WinampTheme.pixelFont)
                .foregroundColor(disabled ? color.opacity(0.35) : color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(width: width, height: height)
                .background(WinampTheme.btnFace)
                .contentShape(Rectangle())
                .modifier(BevelChooser(inset: pressed))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !disabled { pressed = true } }
                .onEnded   { _ in pressed = false }
        )
    }
}

private struct BevelChooser: ViewModifier {
    let inset: Bool
    func body(content: Content) -> some View {
        if inset { content.bevelIn() } else { content.bevelOut() }
    }
}

// MARK: - Pill badge (like STEREO / MONO in the mockup)

struct PillBadge: View {
    let text: String
    let on: Bool
    var activeColor: Color = WinampTheme.lcdGreen
    var body: some View {
        Text(text)
            .font(WinampTheme.smallFont)
            .foregroundColor(on ? activeColor : WinampTheme.lcdGreenDim.opacity(0.45))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(WinampTheme.lcdBg)
            .bevelIn()
    }
}
