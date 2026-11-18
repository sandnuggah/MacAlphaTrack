import AppKit
import QuartzCore
import Combine
import AlphaTrackDriver

/// The menu bar item and its menu: a status row (text and dot) followed
/// by ordinary menu items, in the style of Tailscale's menu.
final class StatusItemController: NSObject {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let header = HeaderView()
    private var subscription: AnyCancellable?
    private var visibilityObservation: NSKeyValueObservation?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // The icon can be hidden from Settings or by Cmd-dragging it off the menu bar.
        statusItem.behavior = .removalAllowed
        statusItem.isVisible = model.showMenuBarIcon
        visibilityObservation = statusItem.observe(\.isVisible, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, self.model.showMenuBarIcon != item.isVisible else { return }
                self.model.showMenuBarIcon = item.isVisible
            }
        }

        if let button = statusItem.button {
            // Fixed template glyph regardless of device state: the bundled fader icon,
            // or an SF Symbol when running outside the app bundle.
            let image = Bundle.main.image(forResource: "MenuBarIcon")
                ?? NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "MacAlphaTrack")
            image?.isTemplate = true
            image?.accessibilityDescription = "MacAlphaTrack"
            button.image = image
        }

        let headerItem = NSMenuItem()
        headerItem.view = header
        menu.addItem(headerItem)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit MacAlphaTrack", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        subscription = model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
        refresh()
    }

    private func refresh() {
        if statusItem.isVisible != model.showMenuBarIcon { statusItem.isVisible = model.showMenuBarIcon }
        header.statusLabel.stringValue = model.statusText
        let color: NSColor
        switch model.state {
        case .connected: color = .systemGreen
        case .waitingForDevice: color = .systemOrange
        case .stopped: color = .systemGray
        }
        header.dot.layer?.backgroundColor = color.cgColor
        header.pulsing = model.state == .waitingForDevice
    }

    @objc private func openSettings() { model.showMainWindow() }
    @objc private func quit() { model.quit() }
}

/// The first menu row: the connection status in the menu's own font, with a status dot
/// centred over the shortcut column. Sized like an ordinary menu item.
final class HeaderView: NSView {
    let statusLabel = NSTextField(labelWithString: "")
    /// Connection status: green connected, orange waiting, grey stopped.
    let dot = NSView()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        statusLabel.font = .menuFont(ofSize: 0)
        statusLabel.textColor = .labelColor
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        for v in [statusLabel, dot] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: dot.leadingAnchor, constant: -8),
            dot.centerXAnchor.constraint(equalTo: trailingAnchor, constant: -30),  // centre of the shortcut column
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Fade the dot in and out, as a "waiting" cue.
    var pulsing = false {
        didSet { if pulsing != oldValue { updatePulse() } }
    }

    // Layer animations are dropped when the view leaves its window (the menu closing),
    // so re-apply each time the menu opens.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updatePulse()
    }

    private func updatePulse() {
        guard let layer = dot.layer else { return }
        layer.removeAnimation(forKey: "pulse")
        guard pulsing, window != nil else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.25
        fade.duration = 0.9
        fade.autoreverses = true
        fade.repeatCount = .infinity
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fade, forKey: "pulse")
    }
}
