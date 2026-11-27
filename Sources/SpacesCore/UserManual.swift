import Foundation

/// The user manual shown by Help › User manual. Mirrors `docs/08-user-manual.md`
/// word for word (a unit test keeps the two in step), so the app needs no
/// bundled files and the manual works offline.
public enum UserManual {
    public static let markdown = #"""
# Dispaces User Manual

Dispaces shows your Spaces (desktops) as small square tiles in the macOS menu bar and switches Space when you click one. Spaces with the same name on different displays form one logical space: one tile, and one click switches every display to it. There is no Dock icon except while one of its windows is open.

## Getting started

- **Turn on the desktop shortcuts.** System Settings › Keyboard › Keyboard Shortcuts › Mission Control: turn on "Switch to Desktop 1", "Switch to Desktop 2" and so on, one for each desktop. Dispaces switches by pressing these for you.
- **Allow Accessibility.** The first click on a tile asks for it. It's used only to press the Switch to Desktop shortcuts.
- **Name your Spaces.** Give the Spaces that belong together the same name on every display, for example Home, Music and Tech. Rename them in Manage displays and spaces (double-click a column heading or a Space).
- **Check the setup.** Right-click the tiles › Setup check… shows what's on and what's missing. An amber **!** after the tiles means something needs attention; click it.
- **Keep it in view.** Hold Command and drag the tiles towards the clock. macOS hides the menu bar items furthest from the clock first when they don't fit (for example beside the notch), and Dispaces remembers where you put it.

## Logical spaces

- **Same name, same logical space.** A display's Space named Home and another display's Space named Home are one logical space, Home. Upper and lower case don't matter.
- **Numbered 1, 2, 3…** in the order the names first appear: the main display's Spaces from left to right in Mission Control, then names that only other displays have.
- **A display without that Space** simply isn't switched. Manage displays and spaces shows it as "Not assigned".
- **A Space you haven't named** ("Desktop N") is a logical space of its own, so it switches only its own display.
- **Two Spaces with the same name on one display:** the second one gets its own logical space.
- **Renaming a Space moves it** to the logical space with the new name.
- **Letters instead of numbers:** in Manage displays and spaces, type up to 2 characters in a logical space's Tile displayed field, for example H for Home. Its tile then shows H instead of 1; the numbering itself doesn't change. Leave the field empty to show the number again.
- **The letter belongs to the name:** renaming the logical space takes its letter along (unless the new name has one already). A Space renamed into another logical space shows that one's letter.

## The tiles in the menu bar

- **One tile per logical space,** showing its number, or the letter you chose for it (Tile displayed). After them come full-screen apps' Spaces (dashed border, "FS").
- **Strong orange:** the display you're working on (the one with the keyboard focus) shows this logical space. After a plain click, every display shows the same number, so that number is strong.
- **Pale orange:** another display shows this logical space, but the display you're working on doesn't, for example after an Option-click, or when a display has no Space for the number you clicked. Click into a window on another display and the colours change to that display's view.
- **One picture for every menu bar:** macOS shows the same Dispaces item on every display's menu bar, so all menu bars show the colours of the display you're working on. Manage displays and spaces shows which Space each display is actually showing.
- **Names:** point at a tile to see its name (in the apps column when Show apps on hover is on, otherwise as a tooltip).
- **First Space of a display:** the built-in display shows its first Space; external displays don't. To change that, see Settings in the preferences file.
- **Unplugged displays:** macOS moves an unplugged display's Spaces onto a connected display. Dispaces keeps them in their logical spaces, so they get no tiles of their own: rest on a tile to see their apps under the unplugged display's (faded) name. A click switches only connected displays, each to its own Space; the unplugged display's Space stays where macOS put it. A name only an unplugged display has keeps its own tile, which shows that Space where it is now.
- **Plugging in or unplugging a display:** about a second later Dispaces redraws all tiles from scratch, as if it had been restarted.
- **The menu:** right-click (or Control-click) the tiles, or click in the gap between two groups.

## When the menu bar item is hidden

macOS decides which menu bar items are shown. It hides items that don't fit, hides the whole menu bar over full-screen apps or when it's set to hide automatically, and lets you switch items off in System Settings › Menu Bar.

- **Floating bar:** whenever macOS isn't showing the tiles for more than a second, a small floating bar with the same tiles appears at the top centre of the main display. It works the same way, and disappears as soon as the menu bar item is back.
- Turn it off in Manage displays and spaces › Advanced › Floating bar when the menu bar item is hidden.

## Switching Space

- **Click a tile** to switch every display to its Space in that logical space. It doesn't matter which display's menu bar you click. The displays switch one after another; the display you clicked on goes last, so you stay where you are.
- **Option-click a tile** to switch only the display whose menu bar you clicked. If that display has no Space in that logical space, a short message says so.
- The switch happens when you let go of the button, within half a second and without moving. **Press and hold** doesn't switch.
- If a switch fails, the tile gets a red ring and a short message under the tiles names the display and says how to fix it. The other displays still switch.

## Naming Spaces and displays

Renaming happens only in Manage displays and spaces; the menu bar's menu has no Rename.

- **Rename a logical space:** double-click (or right-click) its column heading in Manage displays and spaces. Every display's Space in it gets the new name. Up to 24 characters. Leave it empty to give each Space its default name ("Desktop N") back.
- **Rename one Space:** double-click it in Manage displays and spaces. It then belongs to the logical space with that name.
- **Rename a display:** in Manage displays and spaces, double-click its name or right-click it › Rename display…. Right-click › Reset to default name undoes it.

## Apps on a Space

- **Rest the pointer on a tile** for about a third of a second: a column opens under it with the name and every app that has a window there, frontmost first. A long list scrolls. For a logical space on several displays, the apps are listed under each display's name; an unplugged display's name is faded.
- **Display tiles:** when the logical space has a Space of an unplugged display, tiles under its name, one per line, show every display with a Space in it, the unplugged one's name faded. Click one to go to that display's Space; the one on screen now is orange.
- **Move into the column** and it stays open. Each app glows under the pointer.
- **Click an app** to switch there and bring the app to the front, as clicking it in the Dock would. An app under an unplugged display's name takes you to that display's Space, on the display macOS moved it to.
- Turn it off in Manage displays and spaces › Advanced › Show apps on hover. Dispaces reads only which apps have windows where, never window titles or contents.

## Moving a window to another Space (Option-Control drag)

- Turn it on once: Manage displays and spaces › Advanced › Option-Control-drag windows to Spaces.
- **Grab a window** by its title bar first, then hold Option and Control, and drag the pointer onto a tile in the menu bar (or on the floating bar). Grab first: Control-clicking a title bar is a right-click.
- The tile gets a thick ring; when it has had it for a moment, the display you're dragging on switches to its Space in that logical space, and macOS carries the window along. Then let go.
- Only that display switches. A tile whose logical space has no Space on that display doesn't react.
- Dispaces never moves windows itself; you hold the window and it presses the desktop shortcut.

## Manage displays and spaces

The menu › Manage displays and spaces opens a normal window you can close, minimise and resize. It opens in front of all other windows, ready to use. Like the manual window, it shows on every desktop, so it stays with you when you switch Space.

- **A grid of the connected displays:** one column per logical space and one row per display, in macOS's display order. Each column's heading has three rows: Tile number, Tile name and Tile displayed. Each cell is that display's Space, or "Not assigned" with the display's name when it has none. A Space is strong orange when it's the one on screen (in the disconnected displays' bars too), pale when another Space of its logical space is; the headings follow the display you're working on.
- **Click a column heading** to switch every display; **click a Space** to switch only its display. **Rest on either** to see the apps, the same as in the menu bar. After a switch the window comes back in front of other windows and keeps the focus.
- **Double-click a heading** to rename the logical space on every display; **double-click a Space** to rename just that one.
- **Tile displayed:** type up to 2 characters (letters, digits or an emoji) to show on the menu bar tile instead of the number. Enter or Tab saves it, and so does clicking elsewhere or leaving the window; Tab moves on to the next column. An empty field shows the number, greyed.
- **Drag a Space onto "Not assigned"** in its own row: it gets that column's name and moves into that column.
- **Disconnected displays** follow, each as a bar with a dashed border. Drag one of their Spaces onto the row of the display macOS moved it to (that row lights up): it then belongs to that display. Windows and Spaces don't move; macOS doesn't let apps move a Space to another display.
- **Forget:** drops an unplugged display you won't use again. Its Spaces join the displays they're on.
- **Undo and redo:** Command-Z undoes a rename, Tile displayed change, drag or Forget; Shift-Command-Z redoes it, while the window is open.
- **Advanced,** at the bottom: tick boxes for Floating bar when the menu bar item is hidden, Show apps on hover, Option-Control-drag windows to Spaces and Launch at login. A change takes effect at once.
- A desktop shown dimmed as "–" was deleted by macOS when the display was unplugged (macOS removes an unplugged display's first desktop).

## Settings in the preferences file

Whether a display's first Space is shown is set in Dispaces' preferences file, not in a window. Type these in Terminal; Dispaces picks the change up on its next refresh (or the menu › Refresh now).

- **Show external displays' first Space:** defaults write io.github.kosrodka.SpacesBar firstSpaceExternal -bool true
- **Hide the built-in display's first Space:** defaults write io.github.kosrodka.SpacesBar firstSpaceBuiltIn -bool false
- **Back to the defaults:** defaults delete io.github.kosrodka.SpacesBar firstSpaceExternal (and the same with firstSpaceBuiltIn).
- A Mac without a built-in display (or with its lid closed) has only external displays, so by default no first Space is shown. A hidden first Space is still there: its Switch to Desktop shortcut and Mission Control still reach it.

## Help

- **Help › Current release** shows the version you're running and what's in it.
- **Help › User manual** opens this manual.

## Keyboard and mouse shortcuts

- **Click a tile:** switch every display to that logical space.
- **Option-click a tile:** switch only the display whose menu bar you clicked.
- **Right-click or Control-click the tiles:** the menu.
- **Command-drag the tiles:** move them along the menu bar.
- **Double-click a heading, Space or display name in Manage displays and spaces:** rename it.
- **Grab a window, then hold Option and Control and drag it onto a tile:** move it to that Space (when turned on).
- **Command-Z / Shift-Command-Z:** undo / redo in Manage displays and spaces.
- **Command-W / Command-M:** close / minimise the Manage and manual windows.
- **Command-Q** (in the menu): quit Dispaces.
- **Control-1, Control-2 …** (macOS's own Switch to Desktop shortcuts) keep working as usual.

## The menu

- **Manage displays and spaces** first, on its own (renaming, and the on/off settings in its Advanced section).
- Below a line: **Setup check…**, **Refresh now** and **Help**; then **Quit Dispaces**.

## Privacy and limits

- No network access, no scripts, no other permissions than Accessibility. Dispaces writes only its own preferences.
- Desktops 1 to 16 switch with one shortcut. macOS has no shortcut beyond 16, so those desktops, like a full-screen app's Space, are reached step by step, and only on the display under the pointer.
- macOS has no shortcut that switches all displays at once, so a logical space is switched one display after another.
- macOS alone decides whether the menu bar item fits; when it doesn't, the floating bar stands in.
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
        "Logical spaces: Spaces with the same name on different displays share one tile; one click switches every display.",
        "Tile displayed: show a letter (H for Home) on a tile instead of its number, set in Manage displays and spaces.",
        "The on/off settings moved from the menu to Manage displays and spaces › Advanced.",
        "An unplugged display's Spaces stay in their logical spaces: no extra tiles, and their apps show on hover under its faded name.",
        "Hover a logical space with an unplugged display's Space: a tile per display takes you to that display's Space.",
        "Option-click a tile to switch only the display whose menu bar you clicked.",
        "Orange highlight: strong for the number the display you're working on shows, pale for numbers only other displays show.",
        "Manage displays and spaces is a grid: one column per logical space, one row per display, with renames, drag and undo.",
        "Option-Control-drag a window onto a tile to move it to that Space (off until turned on).",
        "First Spaces: shown on the built-in display, hidden on external displays; changeable in the preferences file.",
        "Rest on a tile to see its apps; click an app to switch there and bring it forward. Readable in Dark mode again.",
        "A small floating bar stands in whenever macOS hides the menu bar item (can be turned off).",
        "Help menu with this note and the user manual.",
    ]
}
