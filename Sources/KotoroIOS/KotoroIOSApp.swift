import SwiftUI
import KotoroUI

/// iOS app layer. SwiftUI + the on-device engine the iPhone ships with; the
/// shared surface lives in `KotoroUI`, so iOS and macOS stay identical.
@main
struct KotoroIOSApp: App {
    var body: some Scene {
        WindowGroup {
            KotoroRootView()
        }
    }
}
