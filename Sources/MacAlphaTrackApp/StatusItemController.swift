import AppKit
import Combine
import AlphaTrackDriver

/// The menu bar item and its menu: a header row (name and status) followed
/// by ordinary menu items, in the style of Tailscale's menu.
final class StatusItemController: NSObject {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let header = HeaderView()
    private var subscription: AnyCancellable?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

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
        header.titleLabel.stringValue = "MacAlphaTrack"
        header.subtitleLabel.stringValue = model.statusText
    }

    @objc private func openSettings() { model.showMainWindow() }
    @objc private func quit() { model.quit() }
}

/// Title and subtitle, laid out like a two-line menu header.
final class HeaderView: NSView {
    let titleLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 34))
        titleLabel.font = .menuFont(ofSize: 0)           // same size as the menu items (13 pt)
        subtitleLabel.font = .systemFont(ofSize: 11)      // small secondary line, like Tailscale's
        subtitleLabel.textColor = .secondaryLabelColor
        for v in [titleLabel, subtitleLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 0),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
