import SwiftUI
import AlphaTrackDriver

/// The menu bar panel: status at a glance, on/off, log, and a way to the main window.
struct MenuPanelView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var showLog = false

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
                Button(showLog ? "Hide log" : "Show log") { showLog.toggle() }
                Spacer()
                Button("Quit") { model.quit() }.keyboardShortcut("q")
            }
            if showLog { LogView() }
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

struct LogView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(model.logLines.suffix(30).enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 10, design: .monospaced))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 140)
        .padding(6)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
    }
}

/// The main window: setup that you do once, kept out of the menu bar panel.
struct MainWindow: View {
    static let id = "main"
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Driver") {
                    HStack {
                        Circle().fill(model.state == .connected ? .green : model.state == .waitingForDevice ? .orange : .gray)
                            .frame(width: 9, height: 9)
                        Text(model.statusText)
                    }
                }
                Toggle("Run the driver", isOn: $model.driverEnabled)
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }))
                    .disabled(!model.isBundled)
                if !model.isBundled {
                    Text("Launch at login is available when running as MacAlphaTrack.app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("General")
            }

            Section {
                LabeledContent("Status", value: liveStatusText)
                LabeledContent("Location") {
                    HStack {
                        Text(model.liveDestinationPath)
                            .font(.caption).foregroundStyle(.secondary)
                            .truncationMode(.middle).lineLimit(1)
                            .help(model.liveDestinationPath)
                        Button("Change…") { model.chooseLiveFolder() }
                    }
                }
                HStack {
                    Button(liveButtonTitle) { model.installLiveScript() }
                        .disabled(!model.liveSourceAvailable)
                    if model.liveStatus != .notInstalled {
                        Button("Reveal in Finder") { model.revealLiveScript() }
                    }
                }
                Text("After installing, restart Live. Then in Preferences › Link, Tempo & MIDI choose Control Surface “AlphaTrack” with Input and Output “AlphaTrack”. Start MacAlphaTrack before Live so the ports exist.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Ableton Live control surface")
            }

            if let error = model.lastError {
                Section {
                    Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
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

    private var liveButtonTitle: String {
        switch model.liveStatus {
        case .notInstalled: return "Install"
        case .installed: return "Reinstall"
        case .outdated: return "Update"
        case .symlink: return "Install copy"
        }
    }
}
