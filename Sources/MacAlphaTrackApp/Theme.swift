import SwiftUI
import AppKit

enum Theme {
    /// Main window background (and title bar).
    static let window = Color(red: 30 / 255, green: 71 / 255, blue: 148 / 255)
    static let windowNSColor = NSColor(srgbRed: 30 / 255, green: 71 / 255, blue: 148 / 255, alpha: 1)
    /// Section cards inside the window.
    static let section = Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255)
}

/// A settings-style card: rows separated by dividers on the section colour.
struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .background(Theme.section)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// One row inside a SectionCard. Put a `RowDivider()` between rows.
struct Row<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }

}

struct RowDivider: View {
    var body: some View {
        Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 14)
    }
}

/// Paints the hosting NSWindow's title bar with the window colour. Applied when the
/// helper view actually joins a window, not on a timer.
struct WindowStyler: NSViewRepresentable {
    final class StylerView: NSView {
        private var observation: NSKeyValueObservation?
        private var observedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== observedWindow else { return }
            observedWindow = window
            apply(window)
            // SwiftUI and AppKit flip titlebarAppearsTransparent back to false after the
            // window is configured (and again under the current design). Pin it with KVO.
            observation = window.observe(\.titlebarAppearsTransparent, options: [.new]) { w, _ in
                if !w.titlebarAppearsTransparent {
                    DispatchQueue.main.async { w.titlebarAppearsTransparent = true }
                }
            }
        }

        private func apply(_ window: NSWindow) {
            // The title bar shows the window's background colour; the SwiftUI content
            // keeps out of the title bar's safe area so it never paints over the controls.
            window.backgroundColor = Theme.windowNSColor
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        }
    }

    func makeNSView(context: Context) -> NSView { StylerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
