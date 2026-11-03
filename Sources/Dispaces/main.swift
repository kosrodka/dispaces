import AppKit

// A menu-bar app: no Dock icon, not in Cmd-Tab (LSUIElement in Info.plist,
// and .accessory here for runs outside the app bundle).
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
