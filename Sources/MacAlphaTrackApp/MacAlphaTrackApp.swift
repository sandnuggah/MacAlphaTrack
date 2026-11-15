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

        Window("MacAlphaTrack", id: MainWindow.id) {
            MainWindow()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
