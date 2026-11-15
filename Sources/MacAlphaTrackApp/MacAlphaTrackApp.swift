import SwiftUI
import AlphaTrackDriver

@main
struct MacAlphaTrackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The only SwiftUI scene is the settings window, so nothing opens at launch;
        // the menu bar item is an AppKit NSStatusItem (see StatusItemController).
        Settings {
            MainWindow()
                .environmentObject(delegate.model)
        }
    }
}
