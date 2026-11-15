import Foundation
import AppKit
import ServiceManagement
import AlphaTrackDriver

/// Observable state behind the menu bar UI: the driver, the Live installer, login item.
final class AppModel: ObservableObject {
    @Published var state: DriverService.State = .stopped
    @Published var activity = DriverService.Activity()
    @Published var logLines: [String] = []
    @Published var lastError: String?
    @Published var driverEnabled: Bool {
        didSet {
            UserDefaults.standard.set(driverEnabled, forKey: "driverEnabled")
            driverEnabled ? startDriver() : stopDriver()
        }
    }
    @Published var liveStatus: LiveScriptInstaller.Status = .notInstalled
    @Published var liveFolder: URL
    @Published var launchAtLogin = false

    private let service = DriverService(verbose: false, callbackQueue: .main)
    private let liveSource = LiveScriptInstaller.bundledSource()

    var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    var liveSourceAvailable: Bool { liveSource != nil }

    var menuBarSymbol: String {
        switch state {
        case .connected: return "slider.vertical.3"
        case .waitingForDevice: return "powerplug"
        case .stopped: return "pause.circle"
        }
    }

    var statusText: String {
        switch state {
        case .connected: return "AlphaTrack connected"
        case .waitingForDevice: return "Waiting for AlphaTrack…"
        case .stopped: return "Driver stopped"
        }
    }

    init() {
        let defaults = UserDefaults.standard
        driverEnabled = defaults.object(forKey: "driverEnabled") as? Bool ?? true
        liveFolder = (defaults.string(forKey: "liveRemoteScriptsFolder").map { URL(fileURLWithPath: $0) })
            ?? LiveScriptInstaller.defaultRemoteScriptsFolder
        service.onStateChange = { [weak self] s in self?.state = s }
        service.onActivity = { [weak self] a in self?.activity = a }
        service.onLog = { [weak self] line in
            guard let self else { return }
            let t = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            logLines.append("\(t)  \(line)")
            if logLines.count > 200 { logLines.removeFirst(logLines.count - 200) }
        }
        refreshLiveStatus()
        refreshLaunchAtLogin()
        if driverEnabled { startDriver() }
    }

    // MARK: driver

    func startDriver() {
        lastError = nil
        do { try service.start() } catch { lastError = "Could not create MIDI ports: \(error.localizedDescription)" }
    }

    func stopDriver() {
        DispatchQueue.global().async { [service] in service.stop() }
    }

    func clearLog() { logLines = [] }

    func quit() {
        service.stop()
        NSApp.terminate(nil)
    }

    // MARK: Live script

    private var installer: LiveScriptInstaller? {
        liveSource.map { LiveScriptInstaller(source: $0, remoteScriptsFolder: liveFolder) }
    }

    var liveDestinationPath: String { liveFolder.appendingPathComponent(LiveScriptInstaller.scriptFolderName).path }

    func refreshLiveStatus() {
        liveStatus = installer?.status() ?? .notInstalled
    }

    func installLiveScript() {
        lastError = nil
        guard let installer else { lastError = "The Live script is missing from this build."; return }
        do { try installer.install() } catch { lastError = "Install failed: \(error.localizedDescription)" }
        refreshLiveStatus()
    }

    func revealLiveScript() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: liveDestinationPath)])
    }

    func chooseLiveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose Live's \"Remote Scripts\" folder (inside the User Library)."
        panel.directoryURL = liveFolder.deletingLastPathComponent()
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            liveFolder = url
            UserDefaults.standard.set(url.path, forKey: "liveRemoteScriptsFolder")
            refreshLiveStatus()
        }
    }

    // MARK: login item

    func refreshLaunchAtLogin() {
        launchAtLogin = isBundled && SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        lastError = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = "Login item: \(error.localizedDescription)"
        }
        refreshLaunchAtLogin()
    }
}
