-- Moveable UI: built-in vital bars
--
-- Replaces only the three ordinary HUD vital meters with independently movable
-- and resizable surfaces. The server-owned IMeter widgets stay alive and keep
-- receiving updates; they are merely hidden while this addon is active.

local DEFAULT_W = 101
local DEFAULT_H = 24

local METERS = {
  ["gfx/hud/meter/hp"] = {
    id = "health",
    label = "HP",
    position = {20, 110},
  },
  ["gfx/hud/meter/stam"] = {
    id = "stamina",
    label = "Stam",
    position = {20, 140},
  },
  ["gfx/hud/meter/nrj"] = {
    id = "energy",
    label = "Energy",
    position = {20, 170},
  },
}

local sessions = {}

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

local function round(value)
  return math.floor(value + 0.5)
end

local function segments(meter)
  local result = {}
  for _, segment in ipairs(meter:segment():list()) do
    result[#result + 1] = clamp(segment:value() or 0, 0, 1)
  end
  return result
end

local function numbers(text)
  local result = {}
  if text then
    for value in text:gmatch("%d+") do
      result[#result + 1] = tonumber(value)
    end
  end
  return result
end

local function nativeTooltip(record)
  local widget = record.meter:widget()
  return widget and widget:exists() and widget:tooltip() or nil
end

local function hpText(record, values)
  local found = numbers(nativeTooltip(record))
  if #found >= 3 then
    return string.format("%d/%d/%d", found[1], found[2], found[3])
  end
  return string.format("%d%% HP", round((values[1] or 0) * 100))
end

local function energyText(record, values)
  local found = numbers(nativeTooltip(record))
  if #found >= 1 then
    return string.format("%d/%d", found[1], found[2] or 10000)
  end
  return string.format("%d/10000", round((values[1] or 0) * 10000))
end

local function frame(g, width, height)
  g:color(15, 12, 8, 235)
  g:rect(0, 0, width, height)
  g:color(224, 190, 105, 210)
  g:rect(1, 1, math.max(1, width - 2), math.max(1, height - 2))
end

local function drawLabel(g, text, width, height)
  g:color(255, 255, 255, 255)
  g:atext(text, width / 2, height / 2, 0.5, 0.5)
end

local function drawHealth(record, g, width, height, values)
  local hard = values[1] or 0
  local soft = values[2] or hard
  g:color(205, 154, 0, 230)
  g:frect(0, 0, math.floor(width * hard), height)
  g:color(216, 0, 0, 240)
  g:frect(0, 0, math.floor(width * soft), height)
  drawLabel(g, hpText(record, values), width, height)
end

local function drawStamina(record, g, width, height, values)
  local value = values[1] or 0
  local first = math.floor(width * math.min(value, 0.25))
  local second = math.floor(width * math.max(0, math.min(value, 0.50) - 0.25))
  local third = math.floor(width * math.max(0, value - 0.50))
  g:color(3, 3, 80, 220)
  g:frect(0, 0, first, height)
  g:color(16, 16, 128, 220)
  g:frect(first, 0, second, height)
  g:color(16, 16, 255, 225)
  g:frect(first + second, 0, third, height)
  drawLabel(g, string.format("%d%% Stam", round(value * 100)), width, height)
end

local function drawEnergy(record, g, width, height, values)
  local value = values[1] or 0
  if value >= 0.80 then
    g:color(72, 190, 92, 225)
  elseif value < 0.20 then
    g:color(220, 80, 80, 225)
  else
    g:color(128, 128, 255, 220)
  end
  g:frect(0, 0, math.floor(width * value), height)
  drawLabel(g, energyText(record, values), width, height)
end

local DRAW = {
  health = drawHealth,
  stamina = drawStamina,
  energy = drawEnergy,
}

local function draw(record, event)
  local g, width, height = event:g(), event:w(), event:h()
  g:color(20, 20, 20, 190)
  g:frect(0, 0, width, height)
  DRAW[record.spec.id](record, g, width, height, segments(record.meter))
  frame(g, width, height)
end

local function destroyRecord(record, restore)
  local native = record.meter and record.meter:widget()
  if restore and native and native:exists() then
    pcall(function() native:visible(true) end)
  end
  if record.panel and record.panel:exists() then
    record.panel:destroy()
  end
end

local function addMeter(state, meter, spec)
  if state.byMeter[meter] then return end
  local native = meter:widget()
  if not (native and native:exists()) then return end

  local hud = state.hud
  local panel = hafen.ui():widget():name(spec.id):parent(hud)
    :position(spec.position[1], spec.position[2]):size(DEFAULT_W, DEFAULT_H)

  local record = {meter = meter, spec = spec, panel = panel}
  state.byMeter[meter] = record

  panel:on("Draw", function(event) draw(record, event) end)
  panel:on("Update", function()
    if not (meter:exists() and panel:exists()) then return end
    local tip = nativeTooltip(record)
    if spec.id == "energy" then
      panel:tooltip("Fullness meter. Above 8000% heals; below 2000% starves.")
    elseif tip then
      panel:tooltip(tip)
    end
  end)

  native:visible(false)
end

local function sync(state)
  if not (state.session:exists() and state.hud:exists()) then return end
  for _, meter in ipairs(state.session:meter():list()) do
    local spec = METERS[meter:res()]
    if spec then addMeter(state, meter, spec) end
  end
  for meter, record in pairs(state.byMeter) do
    if not meter:exists() then
      destroyRecord(record, false)
      state.byMeter[meter] = nil
    end
  end
end

local function attach(session)
  if sessions[session] then return end
  local hud = session:ui():match("@GameUI")
  if not hud then return end
  local state = {session = session, hud = hud, byMeter = {}}
  sessions[session] = state
  sync(state)
end

local function detach(session, restore)
  local state = sessions[session]
  if not state then return end
  for _, record in pairs(state.byMeter) do destroyRecord(record, restore) end
  sessions[session] = nil
end

hafen.event():on("SessionEnteredWorld", function(session) attach(session) end)
hafen.event():on("SessionRemoved", function(session) detach(session, false) end)

-- Meters can arrive before their resource name is ready, so a small periodic
-- reconciliation complements MeterAdded and also handles server-added bars.
hafen.timer():every(0.25, function()
  for _, session in ipairs(hafen.session():list()) do
    if session:exists() and session:character() then
      local state = sessions[session]
      if state and not state.hud:exists() then detach(session, true) end
      if not sessions[session] then attach(session) end
    end
  end
  for _, state in pairs(sessions) do sync(state) end
end)

hafen.event():on("Disable", function()
  for session in pairs(sessions) do detach(session, true) end
end)

-- The shared editor owns handles and saved rectangles. This module renders
-- the three meter surfaces under the same addon owner.
local movable = MoveableUI
movable.register{
  id = "vital-health",
  selector = "[name=movable-ui/health]",
  label = "Health",
  minWidth = 60,
  minHeight = 14,
}
movable.register{
  id = "vital-stamina",
  selector = "[name=movable-ui/stamina]",
  label = "Stamina",
  minWidth = 60,
  minHeight = 14,
}
movable.register{
  id = "vital-energy",
  selector = "[name=movable-ui/energy]",
  label = "Energy",
  minWidth = 60,
  minHeight = 14,
}
