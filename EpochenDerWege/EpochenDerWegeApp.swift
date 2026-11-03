import SwiftUI

@main
struct EpochenDerWegeApp: App {
    var body: some Scene {
        WindowGroup("Epochen der Wege") {
            ContentView()
                .frame(minWidth: 1000, minHeight: 650)
        }
        .defaultSize(width: 1440, height: 900)
    }
}
