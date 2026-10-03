-- Moveable UI: move the client's own combat canvas around a saved screen anchor.
-- Fightsess paints relative to the player. A nested transparent canvas
-- translates that native drawing while a small widget supplies the drag point.

local movable = MoveableUI
local sessions = {}
local ANCHOR_W, ANCHOR_H = 180, 48

local function restore(state)
  if state.native and state.native:exists() then
    pcall(function() state.native:parent(nil) end)
  end
  state.native = nil
end

local function detach(session)
  local state = sessions[session]
  if not state then return end
  restore(state)
  if state.host and state.host:exists() then state.host:destroy() end
  if state.anchor and state.anchor:exists() then state.anchor:destroy() end
  sessions[session] = nil
end

local function place(state)
  if not (state.native and state.native:exists() and state.canvas:exists()
      and state.anchor:exists()) then return end
  local hud = state.hud
  local room = hud:size()
  local hostSize = state.host:size()
  if hostSize.w ~= room.w or hostSize.h ~= room.h then
    state.host:size(room.w, room.h)
  end
  local canvasSize = state.canvas:size()
  if canvasSize.w ~= room.w or canvasSize.h ~= room.h then
    state.canvas:size(room.w, room.h)
  end

  -- The fight canvas uses the player's projected map point as its origin.
  -- worldToScreen returns a root pixel; convert it to HUD coordinates before
  -- moving the canvas so that the native graphics land at our anchor.
  if hafen.session():current() ~= state.session then return end
  local gob = state.session:player():gob()
  local position = gob and gob:position()
  local projected = position and state.session:world():worldToScreen(position)
  if not projected then return end
  local screen = hud:rootPos()
  local anchor = state.anchor:position()
  state.canvas:position(
    math.floor(anchor.x + ANCHOR_W / 2 - (projected.x - screen.x) + 0.5),
    math.floor(anchor.y + ANCHOR_H / 2 - (projected.y - screen.y) + 0.5))
end

local function build(session)
  if not (session and session:exists() and session:character()) then return nil end
  local hud = session:ui():match("@GameUI")
  if not hud then return nil end
  local room = hud:size()
  local anchor = hafen.ui():widget():name("combat-anchor"):parent(hud)
    :size(ANCHOR_W, ANCHOR_H)
    :position(math.max(0, math.floor((room.w - ANCHOR_W) / 2)),
      math.max(0, room.h - ANCHOR_H - 120))
  -- Brodgar fits direct HUD children to the screen. A canvas nested under our
  -- host is exempt, so its position can counter the player's projected point.
  local host = hafen.ui():widget():name("combat-host"):parent(hud)
    :size(room.w, room.h):position(0, 0)
  local canvas = hafen.ui():widget():name("combat-canvas"):parent(host)
    :size(room.w, room.h):position(0, 0)
  local state = {session=session, hud=hud, anchor=anchor, host=host, canvas=canvas}
  sessions[session] = state
  canvas:on("Update", function() place(state) end)
  return state
end

local function sync(session)
  if not movable.combatEnabled() then detach(session); return end
  local state = sessions[session]
  if state and (not state.hud:exists() or not state.anchor:exists()
      or not state.host:exists()
      or not state.canvas:exists()) then detach(session); state = nil end
  if not state then state = build(session) end
  if not state then return end

  local native = session:ui():match("@Fightsess")
  if native ~= state.attemptedNative then
    restore(state)
    state.attemptedNative = native
    if native then
      -- Rehome keeps the original widget, its server updates, hotkeys, draw
      -- code and tooltips. If another addon owns it, leave combat stock.
      local ok, failure = pcall(function() native:parent(state.canvas) end)
      if ok and native:parent() == state.canvas then
        state.native = native
      elseif not ok then
        hafen.log():write("cannot move native combat UI: " .. tostring(failure))
      else
        hafen.log():write("cannot move native combat UI: parent was unchanged")
      end
    end
  end
  state.anchor:visible(movable.unlocked() and state.native ~= nil)
  if state.native then place(state) end
end

movable.register{
  id="combat-interface", selector="[name=movable-ui/combat-anchor]",
  label="Combat interface", resizable=false,
  minWidth=ANCHOR_W, minHeight=ANCHOR_H,
}

movable.onCombatChanged(function(enabled)
  if not enabled then
    for session in pairs(sessions) do detach(session) end
  else
    for _, session in ipairs(hafen.session():list()) do sync(session) end
  end
end)

hafen.event():on("SessionEnteredWorld", function(session) sync(session) end)
hafen.event():on("SessionRemoved", function(session) detach(session) end)
hafen.timer():every(0.25, function()
  for _, session in ipairs(hafen.session():list()) do sync(session) end
  for session in pairs(sessions) do
    if not session:exists() then detach(session) end
  end
end)
hafen.event():on("Disable", function()
  for session in pairs(sessions) do detach(session) end
end)
