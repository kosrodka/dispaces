import AppKit

/// The app's normal windows (Manage displays and spaces, User manual). The app
/// has no main menu, so the window handles the usual shortcuts itself:
/// Command-W close, Command-M minimise, Command-C copy, Command-A select all,
/// Command-Z undo and Shift-Command-Z redo.
///
/// While any of them is open the app shows in the Dock, so a window can be
/// minimised and found again like any other; it goes back to menu-bar only
/// once the last one closes.
///
/// Like the bars, they show on every desktop (as Dock › Options › Assign To ›
/// All Desktops would do), so switching Space never leaves them behind.
@MainActor
final class AppWindow: NSWindow {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        collectionBehavior = [.canJoinAllSpaces]
    }

    /// Shows the window with the app in the Dock, in front and focused.
    func present() {
        NSApp.setActivationPolicy(.regular)
        bringToFront()
    }

    /// Puts the window above every other window first, then asks for focus.
    /// `orderFrontRegardless` raises it even while another app is active (macOS
    /// may decline or delay `activate()`), so it's never left hidden behind them.
    func bringToFront() {
        if isMiniaturized { deminiaturize(nil) }
        orderFrontRegardless()
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }

    /// Call from `windowWillClose`: leaves the Dock if no other window stays open.
    static func closing(_ window: NSWindow?) {
        let others = NSApp.windows.contains { other in
            other is AppWindow && other !== window && (other.isVisible || other.isMiniaturized)
        }
        if !others { NSApp.setActivationPolicy(.accessory) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == .command {
            switch key {
            case "w":
                performClose(nil)
                return true
            case "m":
                performMiniaturize(nil)
                return true
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
            case "z":
                if let undoManager {
                    if undoManager.canUndo { undoManager.undo() } else { NSSound.beep() }
                    return true
                }
            default:
                break
            }
        }
        if flags == [.command, .shift], key == "z", let undoManager {
            if undoManager.canRedo { undoManager.redo() } else { NSSound.beep() }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
