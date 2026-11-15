import SwiftUI
import AlphaTrackDriver

/// Driver log, shown as a section of the main window. Uses an NSTextView: SwiftUI Text in
/// a ScrollView drew later-appended lines upside down inside this hosted window, and a
/// text view is the better fit for a growing log anyway.
struct LogPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 6) {
            LogTextView(text: model.logLines.joined(separator: "\n"))
                .frame(height: 180)
                .background(Color.white.opacity(0.06))
                .cornerRadius(6)
            HStack {
                Text("\(model.logLines.count) lines").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.logLines.joined(separator: "\n"), forType: .string)
                }
                Button("Clear") { model.clearLog() }
            }
        }
    }
}

struct LogTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        let tv = scroll.documentView as! NSTextView
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.textColor = .secondaryLabelColor
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView, tv.string != text else { return }
        let wasAtBottom = scroll.contentView.bounds.maxY >= (tv.bounds.height - 4)
        tv.string = text
        if wasAtBottom || text.isEmpty { tv.scrollToEndOfDocument(nil) }
    }
}

/// The main window: setup that you do once, kept out of the menu bar panel.
struct MainWindow: View {
    static let id = "main"
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionCard(title: "General") {
                Row {
                    HStack {
                        Text("Driver")
                        Spacer()
                        Circle().fill(model.state == .connected ? .green : model.state == .waitingForDevice ? .orange : .gray)
                            .frame(width: 9, height: 9)
                        Text(model.statusText).foregroundStyle(.secondary)
                    }
                }
                RowDivider()
                Row {
                    HStack {
                        Text("MIDI activity")
                        Spacer()
                        Text("\(model.activity.midiIn) in · \(model.activity.midiOut) out")
                            .foregroundStyle(.secondary)
                            .help("MIDI messages received from and sent to the DAW since launch")
                    }
                }
                RowDivider()
                Row {
                    HStack {
                        Text("Launch at login")
                        Spacer()
                        Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                            .toggleStyle(.switch).labelsHidden()
                            .disabled(!model.isBundled)
                    }
                }
                if !model.isBundled {
                    RowDivider()
                    Row {
                        Text("Launch at login is available when running as MacAlphaTrack.app.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            SectionCard(title: "Ableton Live control surface") {
                Row {
                    HStack {
                        Text("Status")
                        Spacer()
                        Circle().fill(liveStatusColor).frame(width: 9, height: 9)
                        Text(liveStatusText).foregroundStyle(.secondary)
                    }
                }
                RowDivider()
                Row {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Location")
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(model.liveDestinationPath)
                                .font(.caption).foregroundStyle(.secondary)
                                .truncationMode(.middle).lineLimit(1)
                                .help(model.liveDestinationPath)
                            Text(model.liveFolderNote).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Button("Change…") { model.chooseLiveFolder() }
                    }
                }
                RowDivider()
                Row {
                    HStack {
                        Button(liveButtonTitle) { model.installLiveScript() }
                            .disabled(!model.liveSourceAvailable)
                        if model.liveStatus != .notInstalled {
                            Button("Reveal in Finder") { model.revealLiveScript() }
                        }
                    }
                }
                RowDivider()
                Row {
                    Text("After installing, restart Live. Then in Preferences › Link, Tempo & MIDI choose Control Surface “AlphaTrack” with Input and Output “AlphaTrack”. Start MacAlphaTrack before Live so the ports exist.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let error = model.lastError {
                SectionCard(title: "Problem") {
                    Row { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                }
            }

            SectionCard(title: "Log") {
                Row { LogPane() }
            }
        }
        .padding(20)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        // Keep the colour out of the title bar's safe area: SwiftUI windows are full-size,
        // and a background that extends under the title bar paints over the title and
        // traffic lights. The title bar shows the window's own background colour instead.
        .background(Theme.window, ignoresSafeAreaEdges: [.horizontal, .bottom])
        .background(WindowStyler())
        .preferredColorScheme(.dark)
        .onAppear { model.refreshLiveStatus(); model.refreshLaunchAtLogin() }
    }

    private var liveStatusText: String {
        switch model.liveStatus {
        case .notInstalled: return "Not installed"
        case .installed: return "Installed, up to date"
        case .outdated: return "Installed, older than this app's copy"
        case .symlink: return "Developer symlink installed"
        }
    }

    private var liveStatusColor: Color {
        switch model.liveStatus {
        case .installed: return .green
        case .outdated, .symlink: return .orange
        case .notInstalled: return .gray
        }
    }

    private var liveButtonTitle: String {
        switch model.liveStatus {
        case .notInstalled: return "Install"
        case .installed: return "Reinstall"
        case .outdated: return "Update"
        case .symlink: return "Install copy"
        }
    }
}
