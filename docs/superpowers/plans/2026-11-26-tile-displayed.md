# Tile displayed Implementation Plan

> **For agentic workers:** executed inline (superpowers:executing-plans). Steps use checkbox (`- [ ]`) syntax.

**Goal:** a logical space's tile can show up to 2 characters chosen by the user instead of its number; fix the unreadable floating boxes in Dark mode.

**Architecture:** labels are stored in `Names` (key `tileLabels`, logical key → label), applied together with Space names as one undoable `NameChange`. `LogicalSpaces.Column` says what its tile shows. AppKit draws it.

**Spec:** `docs/superpowers/specs/2026-11-26-tile-displayed-design.md`

## Global Constraints

- Apple frameworks only; the app writes only its own preferences; no force unwraps on data from preferences.
- Manual text in `UserManual.swift` must match `docs/08-user-manual.md` exactly.

## Review Focus

- Pressing Tab from one field to the next keeps the focus (no grid rebuild on commit).
- A refresh while typing doesn't throw away the typed text.
- Renaming a heading to a name that already has a letter keeps that letter.
- Undo after a heading rename restores both the names and the letter.
- Dark/light switch while a box is shown re-colours it.

### Task 1: Labels in SpacesCore

- `TileLabel.maxLength = 2`, `TileLabel.sanitize(_:) -> String`.
- `Names.labels`, `init(storedSpaces:storedDisplays:storedLabels:)`, `label(forLogicalKey:)`, `setLabel(_:forLogicalKey:liveKeys:)`.
- `NameChange { spaces, labels }`, `Names.apply(_:liveSpaceKeys:liveLabelKeys:) -> NameChange` (returns the inverse).
- `Column.labelKey` (nil for a duplicate column), `Column.displayed(in:) -> String`, `Column.renameChange(to:names:) -> NameChange`.
- Tests first in `NamesTests` and `LogicalSpacesTests`.

### Task 2: AppKit

- `Preferences`: key `tileLabels`. `BarController`: `askNames` → `NameChange?`, `apply(_:) -> NameChange`, logical tile shows `displayed`. Menu bar: shrink text to fit.
- Manage window: three heading rows, label field (commit on end editing, undo, no rebuild on commit, defer reload while editing), heading tile without number (name centred).
- `PanelBoxView` (colours in `updateLayer`) for the apps column, message box and floating bar.

### Task 3: Docs

- Manual (both copies), release highlights, `docs/01` F3/F15, `docs/03`.
