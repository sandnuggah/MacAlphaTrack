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
    @Published var liveStatus: LiveScriptInstaller.Status = .notInstalled
    @Published var liveFolder: URL
    /// Where the current Live folder came from, for the UI.
    @Published var liveFolderNote: String = ""
    @Published var launchAtLogin = false

    private let service = DriverService(verbose: false, callbackQueue: .main)
    private let liveSource = LiveScriptInstaller.bundledSource()

    var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    var liveSourceAvailable: Bool { liveSource != nil }

    var statusText: String {
        switch state {
        case .connected: return "AlphaTrack connected"
        case .waitingForDevice: return "Waiting for AlphaTrack…"
        case .stopped: return "Driver stopped"
        }
    }

    init() {
        let defaults = UserDefaults.standard
        let detected = LiveScriptInstaller.detectUserLibrary()
        if let chosen = defaults.string(forKey: "liveRemoteScriptsFolder") {
            liveFolder = URL(fileURLWithPath: chosen)
            liveFolderNote = "Chosen by you"
        } else if let detected {
            liveFolder = detected.remoteScriptsFolder
            liveFolderNote = "From Live \(detected.liveVersion)'s preferences"
        } else {
            liveFolder = LiveScriptInstaller.defaultRemoteScriptsFolder
            liveFolderNote = "Live's default location (no Live preferences found)"
        }
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
        startDriver()  // the driver runs for as long as the app does
    }

    // MARK: driver

    func startDriver() {
        lastError = nil
        do { try service.start() } catch { lastError = "Could not create MIDI ports: \(error.localizedDescription)" }
    }

    func clearLog() { logLines = [] }

    /// Show the main (settings) window and bring the app forward.
    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // SwiftUI's Settings scene is opened through the app menu's "Settings…" item.
        // Sending showSettingsWindow: directly stopped working on recent macOS, so
        // find that item and perform it; fall back to the selector.
        let appMenu = NSApp.mainMenu?.items.first?.submenu
        if let item = appMenu?.items.first(where: { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command }),
           let action = item.action {
            NSLog("MacAlphaTrack: opening window via menu item '%@' (%@)", item.title, NSStringFromSelector(action))
            NSApp.sendAction(action, to: item.target, from: item)
        } else {
            NSLog("MacAlphaTrack: no Settings menu item found in %@; using selector",
                  (appMenu?.items.map { "\($0.title):\($0.action.map(NSStringFromSelector) ?? "-")" } ?? []).joined(separator: ", "))
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    func quit() { NSApp.terminate(nil) }

    /// Called on termination: blank the unit and release it.
    func stopForQuit() { service.stop() }

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
            liveFolderNote = "Chosen by you"
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
