import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(model: model)
    }

    /// macalphatrack://main opens the window; ?snapshot=path also renders it (debug aid).
    func application(_ application: NSApplication, open urls: [URL]) {
        NSLog("MacAlphaTrack: open URLs %@", urls.map(\.absoluteString).joined(separator: " "))
        for url in urls where url.host == "main" {
            model.showMainWindow()
            if let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "snapshot" })?.value {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if let w = WindowStyler.mainWindow { WindowSnapshot.write(w, to: path) }
                }
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.stopForQuit()
        return .terminateNow
    }
}
