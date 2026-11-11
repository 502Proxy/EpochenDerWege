import SwiftUI

@main
struct EpochenDerWegeApp: App {
    @State private var launch = AppLaunch.start()

    var body: some Scene {
        WindowGroup("Epochen der Wege") {
            Group {
                switch launch {
                case .ready(let app):
                    GameScreen(app: app, session: app.session)
                        // A new or loaded game rebuilds the whole screen, scene included.
                        .id(ObjectIdentifier(app.session))
                case .failed(let message):
                    LaunchErrorView(message: message)
                }
            }
            .frame(minWidth: 1000, minHeight: 650)
        }
        .defaultSize(width: 1440, height: 900)
    }
}

/// Result of assembling the app's dependencies at launch.
enum AppLaunch {
    case ready(GameApp)
    case failed(String)

    static func start() -> AppLaunch {
        do {
            return .ready(try GameApp.makeDefault())
        } catch {
            return .failed(String(describing: error))
        }
    }
}

private struct LaunchErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("The game data could not be loaded.", systemImage: "exclamationmark.triangle")
        } description: {
            Text(verbatim: message)
                .font(.callout.monospaced())
        }
    }
}
