import SwiftUI

@main
struct sysmonApp: App {
    @NSApplicationDelegateAdaptor(SysmonAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
