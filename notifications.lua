-- Moveable UI: built-in Labyrinth-style notification popup.
-- Snapshot new messages from every channel, including System. Never replay
-- scrollback or retain messages on disk. Each notification lasts five seconds.
local movable = MoveableUI
local sessions = {}
local LIFETIME, MAX_MESSAGES = 5, 60

local function chatVisible(session)
  local chat = session:ui():match("[name=simple-chat/window]")
  if not chat then chat = session:ui():match("@ChatUI") end
  return chat and chat:visible() or false
end

local function refresh(state)
  if not state.panel:exists() then return end
  state.panel:visible(movable.unlocked() or (#state.messages > 0 and not chatVisible(state.session)))
end

local function paint(state, event)
  local g, width, height = event:g(), event:w(), event:h()
  if chatVisible(state.session) then
    if movable.unlocked() then
      g:color(210, 220, 235, 255)
      g:text("Hidden chat notifications", 6, 6)
    end
    return
  end
  local y = height - 5
  for index = #state.messages, 1, -1 do
    local line = state.messages[index]
    local text = "[" .. line.channel .. "] " .. line.text
    local wrap = math.max(1, width - 12)
    local measured = hafen.ui():measure(text, {width=wrap})
    local lineHeight = measured.h + 4
    y = y - lineHeight
    -- Clip an oversized newest line at the panel edge instead of hiding all
    -- messages because one line is taller than the panel.
    local top = math.max(0, y)
    g:color(0, 0, 0, 192)
    g:frect(0, top, width, math.min(lineHeight, height - top))
    g:color(255, 255, 255, 255)
    g:text(text, 6, top + 2, {width=wrap, color=line.color})
    if y <= 0 then break end
    y = y - 2
  end
end

local function detach(session)
  local state = sessions[session]
  sessions[session] = nil
  if state and state.panel:exists() then state.panel:destroy() end
end

local function attach(session)
  if not (session and session:exists() and session:character()) then return nil end
  local state = sessions[session]
  if state and state.panel:exists() then return state end
  local hud = session:ui():match("@GameUI")
  if not hud then return nil end
  local room = hud:size()
  local panel = hafen.ui():widget():name("notifications"):parent(hud)
    :position(20, math.max(0, room.h - 140)):size(520, 100):visible(false)
  state = {session=session, panel=panel, messages={}}
  sessions[session] = state
  panel:on("Draw", function(event) paint(state, event) end)
  return state
end

hafen.event():on("MessageAdded", function(message, session)
  local state = attach(session)
  if not state then return end
  local channel = message:channel()
  local speaker = message:speaker()
  local text = message:text() or ""
  if speaker then text = (speaker:name() or "?") .. ": " .. text end
  if text == "" then return end
  local line = {text=text, channel=(channel and channel:name()) or "System",
    color=message:color() or {255,255,255,255}}
  state.messages[#state.messages + 1] = line
  if #state.messages > MAX_MESSAGES then table.remove(state.messages, 1) end
  refresh(state)
  hafen.timer():after(LIFETIME, function()
    if sessions[session] ~= state then return end
    for index, candidate in ipairs(state.messages) do
      if candidate == line then table.remove(state.messages, index); break end
    end
    refresh(state)
  end)
end)

hafen.event():on("SessionEnteredWorld", attach)
hafen.event():on("SessionRemoved", detach)
hafen.timer():every(0.1, function()
  for _, session in ipairs(hafen.session():list()) do
    local state = attach(session)
    if state then refresh(state) end
  end
end)
hafen.event():on("Disable", function()
  for session in pairs(sessions) do detach(session) end
end)

movable.register{
  id="hidden-chat", selector="[name=movable-ui/notifications]",
  label="Hidden chat / System notifications", minWidth=180, minHeight=40,
}
