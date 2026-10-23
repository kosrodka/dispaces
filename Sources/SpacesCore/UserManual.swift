import Foundation

/// The user manual shown by Help › User manual. Mirrors `docs/08-user-manual.md`
/// word for word (a unit test keeps the two in step), so the app needs no
/// bundled files and the manual works offline.
public enum UserManual {
    public static let markdown = #"""
# Dispaces User Manual

Dispaces shows every Space (desktop) of each display in a small floating bar and switches Space when you click one. It lives in the menu bar; there is no Dock icon except while one of its windows is open.

## Getting started

- **Turn on the desktop shortcuts.** System Settings › Keyboard › Keyboard Shortcuts › Mission Control: turn on "Switch to Desktop 1", "Switch to Desktop 2" and so on, one for each desktop. Dispaces switches by pressing these for you.
- **Allow Accessibility.** The first click on a tile asks for it. It's used only to press the Switch to Desktop shortcuts.
- **Check the setup.** Menu bar icon › Setup check… shows what's on and what's missing. An amber **!** on a bar means something needs attention; click it.

## The bars

- **One bar per display.** Each display has its own bar, shown only on that display, holding that display's Spaces.
- **Left to right:** three small buttons, the display's name, then one tile per Space.
- **Tiles:** each shows the desktop number and the Space's name. The current Space of the display you're using is filled blue; the current Space of another display has a blue ring. A full-screen app's Space has a dashed border and "FS" instead of a number.
- **First Space of a display:** shown by default. To hide it, untick "Show first Space" next to that display in Manage displays and spaces.
- **Unplugged displays:** macOS moves an unplugged display's Spaces onto a connected display. Dispaces keeps them grouped after that display's own Spaces, under the unplugged display's name (dimmed).
- **Plugging in or unplugging a display:** about a second later Dispaces rebuilds all its bars from scratch, as if it had been restarted.

## Switching Space

- **Click a tile** to switch to that Space. The switch happens when you let go of the button, within half a second and without moving off the tile.
- **Press and hold** doesn't switch; it's kept for grabbing.
- If a switch fails, the tile turns amber and a short message says why and how to fix it.

## Naming Spaces and displays

- **Rename a Space:** double-click its tile, or right-click (or Control-click) › Rename Space…. Up to 24 characters. Leave it empty to go back to "Desktop N".
- **Rename a display:** double-click its name on the bar, or right-click › Rename display…. Right-click › Reset to default name undoes it.

## Moving, resizing and locking a bar

- **Move:** drag the bar by its background or its display name. Each bar stays on its own display and remembers where you put it.
- **Resize:** point at an edge or corner until the pointer changes and the border lights up, then drag. Tiles and text scale to fit. Double-click the edge to go back to the natural size.
- **Eye button:** hides this bar's Spaces, leaving just the buttons; click again to show them.
- **Padlock button:** locks this bar's position and size. Menu bar icon › Lock all bars locks every bar.
- **Arrow button:** refreshes now. Dispaces normally notices changes at once and also checks every 60 seconds.

## Apps on a Space

- **Rest the pointer on a tile** for about a third of a second: a column opens under it with the Space's full name and the apps that have a window there, frontmost first.
- **Move into the column** and it stays open. Each app glows under the pointer.
- **Click an app** to switch to that Space and bring the app to the front, as clicking it in the Dock would.
- Turn it off with menu bar icon › Show apps on hover. Dispaces reads only which apps have windows where, never window titles or contents.

## Moving a window to another Space (Option-drag)

- Turn it on once: menu bar icon › Option-drag windows to Spaces.
- **Hold Option**, grab a window by its title bar and drag it onto a tile on any bar. The bar glows yellow; when the tile has been yellow for a moment, the Space switches and macOS carries the window along. Then let go.
- Dispaces never moves windows itself; you hold the window and it presses the desktop shortcut.

## Manage displays and spaces

Menu bar icon › Manage displays and spaces opens a normal window you can close, minimise and resize. It opens in front of all other windows, ready to use. Like the manual window, it shows on every desktop, so it stays with you when you switch Space.

- **Bars for every display:** connected displays first, in macOS's display order, then unplugged ones with a dashed border.
- **Click a Space** to switch to it, and **rest on it** to see its apps, the same as on the bars. After a switch the window comes back in front of other windows and keeps the focus, so you can click the next Space straight away.
- **Show first Space:** the checkbox next to each display shows or hides its first Space here and on its bar.
- **Move an unplugged display's Space:** drag it onto the bar of the display macOS moved it to (that bar lights up). It then belongs to that display's bar. Windows and Spaces don't move; macOS doesn't let apps move a Space to another display.
- **Forget:** drops an unplugged display you won't use again. Its Spaces join the bars of the displays they're on.
- **Undo and redo:** Command-Z undoes a move, Forget or checkbox change; Shift-Command-Z redoes it, while the window is open.
- A desktop shown dimmed as "–" was deleted by macOS when the display was unplugged (macOS removes an unplugged display's first desktop).

## Help

- **Help › Current release** shows the version you're running and what's in it.
- **Help › User manual** opens this manual.

## Keyboard and mouse shortcuts

- **Click a tile:** switch to that Space.
- **Double-click a tile, or Control-click / right-click › Rename Space…:** rename it.
- **Double-click a display name:** rename the display.
- **Double-click a bar's edge:** natural size.
- **Option + drag a window onto a tile:** move it to that Space (when turned on).
- **Command-Z / Shift-Command-Z:** undo / redo in Manage displays and spaces.
- **Command-W / Command-M:** close / minimise the Manage and manual windows.
- **Command-Q** (in the menu bar icon's menu): quit Dispaces.
- **Control-1, Control-2 …** (macOS's own Switch to Desktop shortcuts) keep working as usual.

## Menu bar icon

- **Show bars:** hides or shows all bars.
- **Lock all bars**, **Show apps on hover**, **Option-drag windows to Spaces**, **Launch at login:** on/off switches.
- **Manage displays and spaces**, **Setup check…**, **Refresh now**, **Help**, and **Quit Dispaces**.

## Privacy and limits

- No network access, no scripts, no other permissions than Accessibility. Dispaces writes only its own preferences.
- Only desktops 1 to 16 can be switched to; macOS has no shortcut beyond 16.
- A full-screen app's Space can be reached only from its own display's bar.
- The name of a display's first desktop follows the display, since macOS gives that desktop no lasting id.
"""#

    /// One line of the manual, as the help window draws it.
    public enum Block: Equatable, Sendable {
        case title(String)
        case heading(String)
        case bullet([Span])
        case paragraph([Span])
    }

    /// A run of text, bold or plain.
    public struct Span: Equatable, Sendable {
        public let text: String
        public let bold: Bool

        public init(_ text: String, bold: Bool = false) {
            self.text = text
            self.bold = bold
        }
    }

    /// Splits the small Markdown subset the manual uses: `# ` title, `## ` heading,
    /// `- ` bullet, other non-empty lines as paragraphs, `**bold**` inside lines.
    public static func blocks(_ text: String = markdown) -> [Block] {
        text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return nil }
            if line.hasPrefix("## ") { return .heading(String(line.dropFirst(3))) }
            if line.hasPrefix("# ") { return .title(String(line.dropFirst(2))) }
            if line.hasPrefix("- ") { return .bullet(spans(String(line.dropFirst(2)))) }
            return .paragraph(spans(line))
        }
    }

    /// `**` toggles bold; an unpaired `**` leaves the rest plain.
    static func spans(_ line: String) -> [Span] {
        let parts = line.components(separatedBy: "**")
        let paired = parts.count % 2 == 1
        return parts.enumerated().compactMap { index, part in
            guard !part.isEmpty else { return nil }
            let bold = index % 2 == 1 && (paired || index < parts.count - 1)
            return Span(bold ? part : (index % 2 == 1 ? "**" + part : part), bold: bold)
        }
    }
}

/// What Help › Current release shows besides the version number.
public enum ReleaseNotes {
    public static let highlights = [
        "One bar per display, shown only on that display, with Show, Lock and Refresh buttons.",
        "Click a Space to switch to it; press and hold doesn't switch.",
        "Move, resize and lock each bar; positions and sizes are remembered per display.",
        "Rest on a Space to see its apps; click an app to switch there and bring it forward.",
        "Option-drag a window onto a Space to move it there (off until turned on).",
        "Manage displays and spaces: bars for every display, unplugged ones too, Forget, undo and redo.",
        "Show first Space checkbox next to each display (on by default).",
        "The Manage and manual windows show on every desktop.",
        "Help menu with this note and the user manual.",
        "Bars rebuilt from scratch when a display is plugged in or unplugged.",
    ]
}
