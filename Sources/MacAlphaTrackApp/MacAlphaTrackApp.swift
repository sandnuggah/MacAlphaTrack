import SwiftUI
import AlphaTrackDriver

@main
struct MacAlphaTrackApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView()
                .environmentObject(model)
        } label: {
            Image(systemName: model.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        // Also opened by `open macalphatrack://main`.
        Window("MacAlphaTrack", id: MainWindow.id) {
            MainWindow()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .handlesExternalEvents(matching: [MainWindow.id])
    }
}
