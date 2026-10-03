# Moveable UI

One addon for the HUD editor, health/stamina/energy bars, speed selector, quest
objectives, HUD adapters and hidden-chat/System notifications.

## Using the editor

1. Open **Options > AddOns > Moveable UI**.
2. Press **GUI LOCK: ON** to unlock editing. Options closes and a compact editor opens.
3. Drag a blue box to move its widget. Where resizing is supported, drag the
   bottom-right grip or hover the box and press **E** to enter pixel dimensions.
4. Hover a box to reveal its **U/L** lock and **E** edit buttons outside its edge.
   A per-widget lock disables this addon's handles for that widget.
5. Press **GUI LOCK: OFF** to finish. The handles disappear and Options reopens.

The grid and vertical center guide are independent. Center snapping works with
the grid off. **Center / reset widgets...** lists the discovered widgets and
provides individual Center and Reset actions.

## Included modules

- **HUD layouts:** Simple Chat, Simple Minimap, hotbars, native chat, buffs,
  action menu, combat opponents, native minimap and native meters.
- **Vital bars:** movable/resizable health, stamina and energy bars. Native
  meters keep receiving updates and are restored when this addon is disabled.
- **Speed:** moves the real speed selector, preserving its normal input.
- **Quest objectives:** moves the real quest container rather than drawing a duplicate.
- **Combat interface:** optionally moves the client's own combat display to a
  saved screen anchor. Enable **Use movable combat interface** in this addon's
  options, then unlock the GUI to drag its blue box. The native combat widget
  keeps its actions, hotkeys and appearance. Turning the option off restores
  its original placement.
- **Hidden-chat notifications:** new messages from all channels, including
  System, appear for five seconds while Chat is hidden. Existing scrollback is
  not replayed and notification text is not saved. Unlocking exposes the panel
  even when empty.

These are files within one addon, with one enable switch. **What At Tracker**
remains a separate mouse-snapshot diagnostic addon.

## Hidden blue boxes

**Show / hide blue boxes...** controls edit handles only; it does not hide the
actual widgets. Defaults hide Equipment, Character Sheet, Inventory, Kith & Kin,
Action search, Map, NKeyBelt, Native chat, Hidepanel, Pointer, Belt, Creel, Stack
and **localinspect**. Both native LocalInspect widgets and named localinspect
addon surfaces are covered. Explicit saved choices take priority over defaults.

Positions, dimensions, per-widget locks and box visibility are kept per character.

## Widget diagnostics

Press **Scan widgets...** or run `:widgetscan` for a scrollable session-tree
snapshot, including hidden widgets. The window shows the first 250 entries and
the total count.

**Write to log** writes the full report between clear begin/end markers in the
terminal output from which the client was launched. The in-game copy is clipped,
but the terminal receives the complete report.

**Copy...** remains available when terminal output is inconvenient. It opens
manual copy pages: click the field, press **Ctrl+A, Ctrl+C**, paste it, then use
**Next**. Each page is bounded to 256 UTF-8 bytes because native entries render
their whole text into one texture. A full report in one entry can crash the
renderer. The current addon API has no clipboard-write or multiline select-all
control.

## Known limits

- Per-widget locks affect this editor's bindings. Other addons' own drag grips
  require their cooperation.
- The bottom System command line and widget front/back order are not exposed as
  independent layout controls.
- Moving the Multi-session dock needs an addon integration; it is outside the
  session HUD tree.
- Fixed-size widgets do not gain resizing simply because they have an edit box.

## Consolidation and saved settings

Version **0.9.0** merges the former `movable-hud-layout`, `movable-vital-bars`,
`movable-speed-selector`, `movable-quest-objectives` and
`movable-hidden-chat` addons.

The displayed name is **Moveable UI**. The folder and internal ID deliberately
remain `movable-ui` so saved preferences and external registrations retain
their identity. The built-in registration IDs also stay the same. No cache or
savedata files need to be moved or rewritten.

The old addon folders must be outside the client's `addons` directory to avoid
duplicate widgets. The installer archives them under `client/addon-backups`.
Run `:reload` after installation. If Moveable UI was previously disabled,
enable it once in Options.

## Extending it

Other addons can still depend on `movable-ui>=0.9.0` and register a real widget:

```lua
local movable = hafen.client():addons():get("movable-ui"):api()
movable.register{
  id = "my-addon-panel",
  selector = "[name=my-addon/panel]",
  label = "My panel",
  resizable = true,
  minWidth = 60,
  minHeight = 20,
}
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for module ownership and lifecycle notes.
