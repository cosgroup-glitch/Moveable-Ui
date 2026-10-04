# Moveable UI internals

The manifest loads five Lua files into one addon environment, in this order:

| File | Responsibility |
| --- | --- |
| `main.lua` | Discovery, saved rectangles, edit handles, menus, locks, grid, diagnostics and the exported registration API. |
| `hud.lua` | Registers native/other-addon surfaces and the quest parent; hosts the real speed selector directly on the HUD. |
| `vitals.lua` | Builds the three meter surfaces and temporarily hides their native counterparts. |
| `notifications.lua` | Builds the hidden-chat panel and retains only short-lived new messages. |
| `combat.lua` | Registers eight native combat regions, enabled by the combat checkbox. |

`MoveableUI` is a table shared inside this addon's environment. Feature modules
use it directly; they do not import their own addon or declare dependencies on
the retired addons. External addons use the exported API as before.

Each module keeps private session state. Brodgar supports multiple subscribers
to lifecycle events. The editor tears down handles; vital bars restore native
meters; notifications destroy their panel and discard pending message state.
Timers discover already-running sessions after reload as well as new sessions.

Per-character stores can lag behind the character identity during login. The
editor waits for both settings variables before attaching, then retries through
normal discovery. It does not create substitute character settings or repair data.

Registration IDs (`vital-health`, `vital-stamina`, `vital-energy`, `hidden-chat`,
`combat-interface`, `speed-selector`, `native-quest-objectives` and HUD adapter
IDs) remain stable.
The custom surfaces now have names under `movable-ui/`, and their explicit
selectors were updated accordingly. Automatic discovery skips editor-owned
surfaces; registered module surfaces are still discovered explicitly.

Regions are discovered only by role, never by HUD child index. Discovery waits
for a nonzero painted box before remembering them, including inactive sessions
and IP without a target. Dead records release their saved IDs before replacements
are discovered. Combat's checkbox gates all eight registrations. Removing a live
region record calls `revert()` to release its hold and remember binding without
deleting the saved layout; `remember(nil)` is reserved for the user's Reset.
Regions use move handles only: no size writes or resize bindings. The HUD's
command line, notice and hidden-chat regions are registered in `hud.lua`.

When combat movement is enabled and the GUI is unlocked, missing or zero-sized
combat regions get owned edit placeholders. Each placeholder uses its region's
stable ID. Discovery destroys the placeholder before remembering the real region,
avoiding simultaneous bindings under one saved name. Locking, disabling combat
movement and addon teardown destroy placeholders. The compact editor's Draw
combat GUI checkbox binds the same combat option as the Options page.
Placeholder defaults use the measured native sizes. After remembering an owned
placeholder, its size is reapplied so old saved dimensions cannot enlarge it;
the saved position is retained. Small edit boxes identify themselves by tooltip.

Speed lives in an owned HUD container registered under `speed-selector`. The
native Speedget is reparented into it without replacing its drawing or input.
The module restores the native parent before destroying its host on teardown,
and recreates the host if the client replaces the speed widget.

Lua syntax and manifest validation can run without launching the client. Widget
placement, combat drawing and input still need an in-game check after changes.
Run `java -cp ../../lib/luaj-jse-3.0.1.jar lua tests/regions.lua` for mocked
discovery, combat-toggle, replacement and teardown regression checks.
Run `java -cp ../../lib/luaj-jse-3.0.1.jar lua tests/speed.lua` for native speed
hosting, movement, replacement and restore checks.
