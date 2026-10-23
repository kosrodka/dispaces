#ifndef CGS_PRIVATE_H
#define CGS_PRIVATE_H

// Private SkyLight functions, re-exported by CoreGraphics.
// Only read-only calls are declared here; never add calls that change state. If Apple removes a symbol,
// linking fails at build time instead of crashing at run time.

#include <CoreFoundation/CoreFoundation.h>

typedef int CGSConnectionID;

/// The connection to the window server for this process.
extern CGSConnectionID CGSMainConnectionID(void);

/// Returns an array with one dictionary per display:
///   "Display Identifier": CFString (display UUID, or "Main")
///   "Current Space":      CFDictionary ("ManagedSpaceID": CFNumber, ...)
///   "Spaces":             CFArray of CFDictionary ("ManagedSpaceID", "uuid", "type", ...)
/// The caller owns the returned array.
extern CFArrayRef CGSCopyManagedDisplaySpaces(CGSConnectionID cid) CF_RETURNS_RETAINED;

/// The Space that currently has focus (on the display you are using).
extern uint64_t CGSGetActiveSpace(CGSConnectionID cid);

/// Spaces a window is on, for the hover icons. `mask` 7 = all Spaces.
/// `windowIDs` is a CFArray of CFNumber window numbers; returns a CFArray of
/// CFNumber Space ids (ManagedSpaceID). The caller owns the returned array.
extern CFArrayRef CGSCopySpacesForWindows(CGSConnectionID cid, int mask, CFArrayRef windowIDs) CF_RETURNS_RETAINED;

#endif
