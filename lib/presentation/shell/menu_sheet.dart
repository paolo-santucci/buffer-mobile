// menu_sheet.dart — public entry point for the overflow menu (TASK-07)
//
// Formerly displayed the menu as a showModalBottomSheet. Now delegates to
// OverflowPopover (an anchored glass popover bubble, FR-04).
//
// Spec refs: FR-04, FR-05, FR-06, FR-19
// Plan refs: TASK-07 (Wave 2), sp-20260617-liquid-glass-floating-chrome-plan.md
//
// Public API:
//   openMenuSheet(context, {anchorLink, onFind}) → VoidCallback
//
// Signature is backward-compatible with existing call sites in
// buffer_screen.dart (TASK-11 will supply a real anchorLink from the pill).
// When anchorLink is null, a transient LayerLink is created and the popover
// appears anchored to top-left (no target registered). TASK-11 wires the real
// pill CompositedTransformTarget link.
//
// The onFind parameter is accepted for signature compat but is NOT passed to
// the popover (Find/Replace tile is absent from the popover per FR-05 — Find
// moved to the bottom toolbar). Existing callers that inject onFind compile
// without change; the callback is silently dropped.
//
// <!-- CANON GAP: anchored popover bubble anatomy + outside-tap-dismiss rule
//      See overflow_popover.dart for the full canon gap note. -->

import 'package:flutter/material.dart';

import 'package:foglietto/presentation/shell/overflow_popover.dart';

// ---------------------------------------------------------------------------
// openMenuSheet — backward-compatible public entry point
// ---------------------------------------------------------------------------

/// Opens the overflow menu as a floating popover bubble.
///
/// Delegates to [openOverflowPopover]. Returns a [VoidCallback] that
/// programmatically dismisses the popover.
///
/// ### Backward-compatibility
/// This function keeps the same call-site shape as the former
/// `showModalBottomSheet` entrypoint so that `buffer_screen.dart` continues
/// to compile without changes before TASK-11 wires the pill.
///
/// - [anchorLink] — optional; the [LayerLink] attached to the pill's
///   [CompositedTransformTarget]. Defaults to an unregistered [LayerLink]
///   (popover anchors to the screen origin) until TASK-11 supplies the real
///   pill link.
/// - [onFind] — accepted for signature compat; **not used** (Find/Replace
///   tile is absent from the popover per FR-05). Existing callers compile
///   unchanged; the callback is dropped.
VoidCallback openMenuSheet(
  BuildContext context, {
  LayerLink? anchorLink,
  // Accepted for signature compat with existing call sites (buffer_screen.dart).
  // NOT forwarded — Find/Replace tile is absent from the popover per FR-05.
  // ignore: avoid_unused_constructor_parameters
  VoidCallback? onFind,
}) {
  // If no anchorLink is provided, create a transient one.
  // The CompositedTransformFollower will render at the screen origin until
  // TASK-11 wires a real pill CompositedTransformTarget.
  final link = anchorLink ?? LayerLink();

  return openOverflowPopover(context, anchorLink: link);
}
