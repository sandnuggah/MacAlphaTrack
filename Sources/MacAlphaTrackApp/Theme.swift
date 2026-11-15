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
    /// The main window, once it exists (used by the snapshot debug hook).
    static weak var mainWindow: NSWindow?

    final class StylerView: NSView {
        private var observation: NSKeyValueObservation?
        private var observedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== observedWindow else { return }
            observedWindow = window
            WindowStyler.mainWindow = window
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
        }
    }

    func makeNSView(context: Context) -> NSView { StylerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Debug aid: render a window (frame and title bar included) to a PNG file.
/// Triggered by `open "macalphatrack://main?snapshot=/path/to/file.png"`.
enum WindowSnapshot {
    static func write(_ window: NSWindow, to path: String) {
        guard let frame = window.contentView?.superview,
              let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        try? describe(window).write(toFile: path + ".txt", atomically: true, encoding: .utf8)
    }

    static func describe(_ w: NSWindow) -> String {
        func btn(_ k: NSWindow.ButtonType) -> String {
            guard let b = w.standardWindowButton(k) else { return "nil" }
            return "hidden=\(b.isHidden) alpha=\(b.alphaValue) frame=\(b.frame) superHidden=\(b.superview?.isHidden ?? false)"
        }
        var lines = [
            "title=\(w.title) titleVisibility=\(w.titleVisibility.rawValue) transparent=\(w.titlebarAppearsTransparent)",
            "styleMask=\(w.styleMask.rawValue) fullSizeContent=\(w.styleMask.contains(.fullSizeContentView)) titled=\(w.styleMask.contains(.titled))",
            "toolbar=\(String(describing: w.toolbar)) toolbarStyle=\(w.toolbarStyle.rawValue)",
            "frame=\(w.frame) contentFrame=\(w.contentView?.frame ?? .zero) contentLayoutRect=\(w.contentLayoutRect)",
            "backgroundColor=\(String(describing: w.backgroundColor)) appearance=\(w.appearance?.name.rawValue ?? "nil")",
            "close: " + btn(.closeButton), "mini: " + btn(.miniaturizeButton), "zoom: " + btn(.zoomButton),
        ]
        func dump(_ v: NSView, _ depth: Int) {
            guard depth < 4 else { return }
            lines.append(String(repeating: "  ", count: depth) + "\(type(of: v)) frame=\(v.frame) hidden=\(v.isHidden)")
            for sub in v.subviews { dump(sub, depth + 1) }
        }
        if let frame = w.contentView?.superview { dump(frame, 0) }
        return lines.joined(separator: "\n")
    }
}
