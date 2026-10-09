import SwiftUI
import KotoroUI

/// macOS app layer. SwiftUI + whatever local STT engine the Mac ships with;
/// the shared surface lives in `KotoroUI`.
@main
struct KotoroMacApp: App {
    var body: some Scene {
        WindowGroup {
            KotoroRootView()
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .frame(minWidth: 420, minHeight: 560)
        }
    }
}
