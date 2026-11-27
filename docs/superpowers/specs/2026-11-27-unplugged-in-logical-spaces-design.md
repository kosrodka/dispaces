# Unplugged displays stay in their logical spaces (design)

Approved by the owner on 27 Nov 2026 ("go ahead").

## Intent

When a display is unplugged, macOS moves its Spaces onto a connected display. Dispaces showed them as a separate, dimmed group of tiles in the menu bar, outside the logical spaces. The owner wants them to stay in their logical spaces: no extra tiles, and hovering a logical tile lists the unplugged display's apps under its name, as if it were connected, with only that name faded.

## What changes

1. An unplugged display's Spaces join logical spaces by name, as cells of that display (`Cell.display`), placed on the display macOS moved them to (`Cell.onDisplay`). Its displays come after the connected ones, so numbers don't change when it's unplugged.
2. No dimmed group in the menu bar.
3. A click switches each connected display to its own Space in the logical space, as before; the unplugged display's Space stays where it is (its host can show one Space, and its own wins). A logical space only unplugged displays have switches its Space where macOS put it (one per host display). Option-click and Option-Control drag follow the same cells.
4. Highlight counts a Space on the display it's on now: a host showing an unplugged display's Home lights H.
5. Hover: one section per display, the unplugged display's heading faded (connected headings `secondaryLabelColor`, unplugged `tertiaryLabelColor`). Clicking an app in an unplugged display's section goes to that Space, then brings the app forward.
6. The unplugged display's first Space follows the first-Space rule. Its full-screen Spaces become normal "FS" tiles of the display they're on now.
7. Unchanged: the Manage window (dashed bar per unplugged display, drag, Forget). Renaming a logical space renames the unplugged display's Space in it too, so it stays in the logical space.

## Approaches

1. **Cells of the unplugged display, placed on their host (chosen):** keeps "one cell per display" for grouping, duplicates and hover headings; switching uses the host.
2. **Treat them as the host's own Spaces:** simpler, but two Homes on one display become duplicates in separate columns, the opposite of what's wanted.
3. **Keep the dimmed tiles and add hover sections:** contradicts "no separate faded tiles".
