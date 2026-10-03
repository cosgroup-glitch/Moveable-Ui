# Moveable UI internals

The manifest loads five Lua files into one addon environment, in this order:

| File | Responsibility |
| --- | --- |
| `main.lua` | Discovery, saved rectangles, edit handles, menus, locks, grid, diagnostics and the exported registration API. |
| `hud.lua` | Registers native/other-addon surfaces, including speed and the real quest parent. |
| `vitals.lua` | Builds the three meter surfaces and temporarily hides their native counterparts. |
| `notifications.lua` | Builds the hidden-chat panel and retains only short-lived new messages. |
| `combat.lua` | Places the native Fightsess under a movable screen anchor and restores its parent when disabled. |

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

Lua syntax and manifest validation can run without launching the client. Widget
placement, combat drawing and input still need an in-game check after changes.
