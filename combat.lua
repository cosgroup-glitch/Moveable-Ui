-- Native combat regions replace the old camera/player-offset canvas.
-- Each role has one stable per-character saved position across fights.
local movable = MoveableUI
-- Placeholder boxes match the native regions measured in the widget scan.
-- During combat the editor follows the live region's size instead.
local regions = {
  {"combat-interface", "fight.action", "Combat interface", 250, 100, -125, 145},
  {"combat-opening-mine", "fight.opening.mine", "Combat openings: yours", 198, 44, -235, -80},
  {"combat-opening-theirs", "fight.opening.theirs", "Combat openings: target", 198, 44, 55, -80},
  {"combat-ip-mine", "fight.ip.mine", "Combat IP: yours", 39, 28, -94, -28},
  {"combat-ip-theirs", "fight.ip.theirs", "Combat IP: target", 39, 28, 55, -28},
  {"combat-cooldown", "fight.cooldown", "Combat cooldown", 54, 54, -27, 40},
  {"combat-last-mine", "fight.last.mine", "Combat last move: yours", 42, 42, -100, 100},
  {"combat-last-theirs", "fight.last.theirs", "Combat last move: target", 42, 42, 58, 100},
}
for _, region in ipairs(regions) do
  movable.register{
    id=region[1], selector=region[2], label=region[3],
    resizable=false, enabled=movable.combatEnabled,
    preview={w=region[4], h=region[5], x=region[6], y=region[7]},
  }
end
