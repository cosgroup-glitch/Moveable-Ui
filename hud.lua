-- Built-in adapters for real Brodgar widgets. Registration IDs are retained
-- from the former addons so their editor layouts keep the same saved keys.
local movable = MoveableUI
local targets = {
  {"chat", "[name=simple-chat/window]", "Chat", true},
  {"minimap", "[name=simple-minimap/map]", "Minimap", true},
  {"hotbars", "[name=actionbars/bar]", "Hot bar", false, true},
  {"native-chat", "@ChatUI", "Native chat", false},
  {"buffs", "@Bufflist", "Buffs", false},
  {"action-menu", "@MenuGrid", "Action menu", false},
  {"fight-view", "@Fightview", "Combat opponents", false},
  {"native-minimap", "@MiniMap", "Native minimap", false},
  {"native-meters", "@IMeter", "Meter", false, true},
}
for _, target in ipairs(targets) do
  movable.register{id=target[1], selector=target[2], label=target[3],
    resizable=target[4], multiple=target[5]}
end
movable.register{
  id="native-quest-objectives", selector="@QView", parentTarget=true,
  label="Quest objectives", resizable=false,
}
movable.register{
  id="speed-selector", selector="@Speedget", label="Speed",
  resizable=false, minWidth=16, minHeight=12,
}
