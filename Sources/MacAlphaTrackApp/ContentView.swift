import SwiftUI
import AlphaTrackDriver

/// The menu bar panel: status at a glance, on/off, and a way to the main window.
/// Its content is fixed-size on purpose: MenuBarExtra windows grow with their content
/// but do not shrink back, so nothing here expands or collapses.
struct MenuPanelView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(statusColor).frame(width: 10, height: 10)
                Text(model.statusText).font(.headline)
                Spacer()
                Toggle("", isOn: $model.driverEnabled).toggleStyle(.switch).labelsHidden()
                    .help("Run the driver and publish the AlphaTrack MIDI ports")
            }
            Text("MIDI ports “\(MIDIBridge.portName)” · in \(model.activity.midiIn) · out \(model.activity.midiOut)")
                .font(.caption).foregroundStyle(.secondary)
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("Open MacAlphaTrack…") {
                    openWindow(id: MainWindow.id)
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { model.quit() }.keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private var statusColor: Color {
        switch model.state {
        case .connected: return .green
        case .waitingForDevice: return .orange
        case .stopped: return .gray
        }
    }
}

/// Driver log, shown as a section of the main window.
struct LogPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.logLines.enumerated()), id: \.offset) { i, line in
                            Text(line).font(.system(size: 11, design: .monospaced)).id(i)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .textSelection(.enabled)
                }
                .frame(height: 180)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .onChange(of: model.logLines.count) { count in
                    if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
                .onAppear {
                    if !model.logLines.isEmpty { proxy.scrollTo(model.logLines.count - 1, anchor: .bottom) }
                }
            }
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
                        Text("Run the driver")
                        Spacer()
                        Toggle("", isOn: $model.driverEnabled).toggleStyle(.switch).labelsHidden()
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
                        Text(liveStatusText).foregroundStyle(.secondary)
                    }
                }
                RowDivider()
                Row {
                    HStack {
                        Text("Location")
                        Spacer()
                        Text(model.liveDestinationPath)
                            .font(.caption).foregroundStyle(.secondary)
                            .truncationMode(.middle).lineLimit(1)
                            .help(model.liveDestinationPath)
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
        .onOpenURL { url in
            // macalphatrack://main?snapshot=/path.png -> write a rendering of this window (debug aid)
            if let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "snapshot" })?.value {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    if let w = WindowStyler.mainWindow { WindowSnapshot.write(w, to: path) }
                }
            }
        }
    }

    private var liveStatusText: String {
        switch model.liveStatus {
        case .notInstalled: return "Not installed"
        case .installed: return "Installed, up to date"
        case .outdated: return "Installed, older than this app's copy"
        case .symlink: return "Developer symlink installed"
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
