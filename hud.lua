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
  {"hud-command-line", "hud.cmdline", "Command line", false},
  {"hud-message", "hud.message", "HUD notice", false},
  {"hud-chat", "hud.chat", "Native hidden chat", false},
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
  id="speed-selector", selector="[name=movable-ui/speed]", label="Speed",
  resizable=false, minWidth=16, minHeight=12,
}

-- Keep the real speed icons and input, but move their parent onto the HUD.
-- A saved move inside the original panel can be clipped or follow that panel.
local speedSessions = {}
local speedErrors = {}
local function restoreSpeed(session)
  local state = speedSessions[session]
  if not state then return end
  if state.native:exists() then state.native:parent(nil) end
  if state.host:exists() then state.host:destroy() end
  speedSessions[session] = nil
  speedErrors[session] = nil
end
local function syncSpeed(session)
  local state = speedSessions[session]
  if not (session:exists() and session:character()) then restoreSpeed(session); return end
  local hud = session:ui():match("@GameUI")
  local native = session:ui():match("@Speedget")
  if state and (state.native ~= native or state.hud ~= hud or not state.host:exists()) then
    restoreSpeed(session); state = nil
  end
  if not (hud and native and native:exists()) then return end
  local box = native:size()
  if not box or box.w <= 0 or box.h <= 0 then return end
  if not state then
    local point, origin, room = native:rootPos(), hud:rootPos(), hud:size()
    local host = hafen.ui():widget():name("speed"):parent(hud):size(box.w, box.h)
      :position(math.max(0, math.min(point.x - origin.x, room.w - box.w)),
        math.max(0, math.min(point.y - origin.y, room.h - box.h)))
    local ok, failure = pcall(function() native:parent(host):position(0, 0) end)
    if not ok or native:parent() ~= host then
      host:destroy()
      local message = tostring(failure or "parent unchanged")
      if speedErrors[session] ~= message then
        speedErrors[session] = message
        hafen.log():write("cannot detach Speed from its panel: " .. message)
      end
      return
    end
    state = {native=native, hud=hud, host=host}
    speedSessions[session] = state
    speedErrors[session] = nil
  end
  local size = state.host:size()
  if size.w ~= box.w or size.h ~= box.h then state.host:size(box.w, box.h) end
end
hafen.timer():every(0.25, function()
  for _, session in ipairs(hafen.session():list()) do syncSpeed(session) end
  for session in pairs(speedSessions) do
    if not session:exists() then restoreSpeed(session) end
  end
end)
hafen.event():on("SessionRemoved", restoreSpeed)
hafen.event():on("Disable", function()
  for session in pairs(speedSessions) do restoreSpeed(session) end
end)
