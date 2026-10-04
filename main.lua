-- Moveable UI
--
-- Shared layout editor. Feature addons register named surfaces; this addon
-- finds them, remembers their rectangles and gives them the common blue-box
-- move/resize UI while GUI LOCK is off.

local HANDLE = 10
local BADGE_WIDTH = 25
local CENTER_SNAP_DISTANCE = 10
local registrations = {}
local sessions = {}
local sync, attach
local editorWindow, listWindow, visibilityWindow, optionsWindow, editWindow, debugWindow
local errors = {}
local function attempt(key, fn)
  local ok, result = pcall(fn)
  if not ok and errors[key] ~= tostring(result) then
    errors[key] = tostring(result)
    hafen.log():write(key .. ": " .. tostring(result))
  end
  return ok, result
end

-- Options > AddOns > Movable UI is the authoritative menu for edit mode.
local addonOptions = hafen.client():options():addon()
local lockOption = addonOptions:boolean("gui-lock"):default(true):add()
local gridOption = addonOptions:boolean("snap-grid"):default(false):add()
local gridSizeOption = addonOptions:number("grid-size"):range(2, 100):default(25):add()
local centerOption = addonOptions:boolean("center-snap"):default(false):add()
local combatOption = addonOptions:boolean("movable-combat"):default(false):add()
local combatChanged = {}
local lockButton

local function unlocked()
  return not lockOption:value()
end

local function lockText()
  return lockOption:value() and "GUI LOCK: ON" or "GUI LOCK: OFF"
end

local function refreshLockButton()
  if lockButton and lockButton:exists() then lockButton:text(lockText()) end
end

local function closeWindow(window)
  if window and window:exists() then pcall(function() window:destroy() end) end
end

local function validNumber(value)
  return type(value) == "number" and value == value and value > 0
end

-- Native TextEntry renders its entire value to one texture, regardless of
-- field width. Never put the full diagnostic report into a single entry.
local function copyPages(text)
  local pages, first = {}, 1
  while first <= #text do
    local last = math.min(#text, first + 255)
    -- Keep UTF-8 code points intact at page boundaries.
    while last < #text do
      local byte = string.byte(text, last + 1)
      if byte < 128 or byte >= 192 then break end
      last = last - 1
    end
    pages[#pages + 1] = string.sub(text, first, last)
    first = last + 1
  end
  if #pages == 0 then pages[1] = "" end
  return pages
end

-- These defaults affect edit handles only, never the widget's own visibility.
local hiddenDefaults = {
  ["equipment"]=true, ["character sheet"]=true, ["inventory"]=true,
  ["kith & kin"]=true, ["action search"]=true, ["map"]=true,
  ["nkeybelt"]=true, ["native chat"]=true, ["chatui"]=true, ["hidepanel"]=true,
  ["pointer"]=true,
  ["belt"]=true, ["creel"]=true, ["stack"]=true,
  ["localinspect"]=true, ["local inspect"]=true,
}
local function elementLocked(record)
  return record.state.elementLocks[record.visibilityKey] == true
end
local function boxShown(record)
  if record.spec.preview and combatOption:value() and unlocked() then return true end
  local saved = record.state.boxVisibility[record.visibilityKey]
  if type(saved) == "boolean" then return saved end
  local label = string.lower(record.spec.label)
  local kind = string.lower(record.target:type() or "")
  local name = string.lower(record.target:name() or "")
  return not (hiddenDefaults[label] or hiddenDefaults[kind] or name == "localinspect"
    or name:match("^localinspect/") or name:match("/localinspect$"))
end

local function register(spec)
  if type(spec) ~= "table" then error("register takes a table", 0) end
  if type(spec.id) ~= "string" or spec.id == "" then
    error("register requires a non-empty id", 0)
  end
  if type(spec.selector) ~= "string" or spec.selector == "" then
    error("register requires a selector for a real widget", 0)
  end
  if registrations[spec.id] then
    error("a movable UI element named '" .. spec.id .. "' is already registered", 0)
  end
  registrations[spec.id] = {
    id = spec.id,
    selector = spec.selector,
    label = (type(spec.label) == "string" and spec.label ~= "") and spec.label or spec.id,
    resizable = spec.resizable ~= false,
    minWidth = validNumber(spec.minWidth) and spec.minWidth or 16,
    minHeight = validNumber(spec.minHeight) and spec.minHeight or 12,
    remember = spec.remember ~= false,
    manage = true,
    multiple = spec.multiple == true,
    parentTarget = spec.parentTarget == true,
    enabled = spec.enabled,
    preview = spec.preview,
  }
  -- Dependencies may register after SessionEnteredWorld. Discover their
  -- surfaces immediately instead of waiting for another login/reload.
  hafen.timer():after(0, function()
    for _, state in pairs(sessions) do attempt("registration discovery", function() sync(state) end) end
  end)
end

local function snap(value)
  local step = math.max(2, gridSizeOption:value())
  return math.floor((value / step) + 0.5) * step
end

local function snapPosition(record)
  local target = record.target
  if not target:exists() then return end
  local position, box = target:position(), target:size()
  if not (position and box) then return end
  local x, y = position.x, position.y
  if gridOption:value() then x, y = snap(x), snap(y) end
  if centerOption:value() then
    local parent = target:parent()
    local room = record.state.hud:size()
    local origin = parent and parent:rootPos()
    local screen = record.state.hud:rootPos()
    if room and origin and screen then
      local center, guide = origin.x + x + (box.w / 2), screen.x + room.w / 2
      if math.abs(center - guide) <= CENTER_SNAP_DISTANCE then
        x = math.floor(guide - origin.x - (box.w / 2) + 0.5)
      end
    end
  end
  if x ~= position.x or y ~= position.y then target:position(x, y) end
end

local function enforceSize(record, snapToGrid)
  if not record.spec.resizable or not record.target:exists() then return end
  local box = record.target:size()
  if not box then return end
  local width, height = box.w, box.h
  if snapToGrid and gridOption:value() then width, height = snap(width), snap(height) end
  width = math.max(record.spec.minWidth, width)
  height = math.max(record.spec.minHeight, height)
  if width ~= box.w or height ~= box.h then record.target:size(width, height) end
end

local function dropEditor(record)
  local target = record.target
  if record.spec.manage and target and target:exists() then
    pcall(function() target:draggable(nil) end)
    if record.spec.resizable then pcall(function() target:resizable(nil) end) end
  end
  for _, key in ipairs({"grip", "lockBadge", "editBadge", "move"}) do
    closeWindow(record[key])
    record[key] = nil
  end
  record.move, record.grip, record.lockBadge, record.editBadge = nil, nil, nil, nil
  record.toolbarShown = false
end

local function editorDraw(record, event)
  local g, width, height = event:g(), event:w(), event:h()
  if elementLocked(record) then g:color(50, 60, 70, 115)
  else g:color(24, 100, 190, 115) end
  g:frect(0, 0, width, height)
  g:color(86, 188, 255, 255)
  g:rect(0, 0, width, height)
  if width >= 45 and height >= 14 then
    local text = hafen.ui():measure(record.spec.label)
    if text.w <= width - 4 then
      g:atext(record.spec.label, width / 2, height / 2, 0.5, 0.5)
    end
  end
end

local openElementEditor
local function toolbarHeight(record)
  local height = 0
  for _, key in ipairs({"lockBadge", "editBadge"}) do
    local item = record[key]
    local size = item and item:exists() and item:size()
    if size then height = math.max(height, size.h) end
  end
  return height
end

local function toolbarPosition(hud, root, screen, box, height)
  local room = hud:size()
  local x = math.max(0, math.min(root.x - screen.x, room.w - (BADGE_WIDTH * 2 + 2)))
  local top = root.y - screen.y
  local y = top >= height and top - height or top + box.h
  return x, y
end

local function badge(record, hud, name, x, y, caption, action)
  -- Keep the handle before any setter can throw. Brodgar enforces each
  -- control's artwork minimum; width-only sizing preserves its native height.
  local item = hafen.ui():button()
  record[name == "lock" and "lockBadge" or "editBadge"] = item
  item:visible(false)
  item:name(name .. "-" .. record.instanceId):parent(hud)
    :position(x, y):text(caption):size(BADGE_WIDTH)
  if name == "lock" then
    item:tooltip(elementLocked(record) and "Locked: click to unlock this widget" or
      "Unlocked: click to lock this widget")
  else
    item:tooltip("Edit this widget's size")
  end
  item:on("Pressed", function() hafen.timer():after(0, action) end)
  return item
end

local arm
local function buildEditor(record)
  if record.move or not unlocked() or not boxShown(record) then return end
  local target = record.target
  if not target:exists() then return end
  local box = target:size()
  if not box or box.w <= 0 or box.h <= 0 then return end

  -- The blue box is the move handle. The corner is added second so it wins
  -- presses in the overlap and performs resizing instead.
  -- Native QView and several HUD widgets do not draw their children. A HUD
  -- sibling handle follows the real target and drives its position directly.
  local hud = record.state.hud
  local origin, point = hud:rootPos(), target:rootPos()
  local move = hafen.ui():widget()
  record.move = move
  move:name("handle-" .. record.instanceId):parent(hud)
    :position(point.x - origin.x, point.y - origin.y):size(box.w, box.h)
    :tooltip(record.spec.label)
  move:on("Draw", function(event) editorDraw(record, event) end)
  move:on("Update", function()
    if not (target:exists() and move:exists()) then return end
    local size = target:size()
    if size then
      if size.w <= 0 or size.h <= 0 then
        move:visible(false)
        if record.lockBadge then record.lockBadge:visible(false) end
        if record.editBadge then record.editBadge:visible(false) end
        return
      end
      move:visible(true)
      local root, screen = target:rootPos(), hud:rootPos()
      move:position(root.x - screen.x, root.y - screen.y)
      move:size(size.w, size.h)
      if record.grip and record.grip:exists() then
        record.grip:position(root.x - screen.x + math.max(0, size.w - HANDLE),
          root.y - screen.y + math.max(0, size.h - HANDLE))
      end
      if record.lockBadge and record.lockBadge:exists() then
        local height = toolbarHeight(record)
        local tx, ty = toolbarPosition(hud, root, screen, size, height)
        record.lockBadge:position(tx, ty)
        local mouse = hafen.ui():mouse()
        local mx, my = mouse:x() - screen.x, mouse:y() - screen.y
        local bx, by = root.x - screen.x, root.y - screen.y
        local overBox = mx >= bx and mx < bx + size.w and my >= by and my < by + size.h
        local overToolbar = mx >= tx and mx < tx + BADGE_WIDTH * 2 + 2
          and my >= ty and my < ty + height
        record.toolbarShown = overBox or (record.toolbarShown == true and overToolbar)
        record.lockBadge:visible(record.toolbarShown)
        if record.editBadge and record.editBadge:exists() then
          record.editBadge:visible(record.toolbarShown)
        end
      end
      if record.editBadge and record.editBadge:exists() then
        local tx, ty = toolbarPosition(hud, root, screen, size, toolbarHeight(record))
        record.editBadge:position(tx + BADGE_WIDTH + 2, ty)
      end
    end
  end)
  record.move = move
  local tx, ty = toolbarPosition(hud, point, origin, box, 0)
  record.lockBadge = badge(record, hud, "lock", tx, ty,
    elementLocked(record) and "L" or "U", function()
      record.state.elementLocks[record.visibilityKey] = not elementLocked(record)
      dropEditor(record)
      arm(record)
    end)
  record.editBadge = badge(record, hud, "edit", tx + BADGE_WIDTH + 2, ty,
    "E", function() openElementEditor(record) end)
  if record.spec.manage and not elementLocked(record) then
    local ok, failure = pcall(function() target:draggable(move) end)
    if not ok and not record.moveError then
      record.moveError = true
      hafen.log():write("cannot arm '" .. record.spec.label .. "' for moving: " .. tostring(failure))
    end
    if not ok then
      if record.lockBadge then record.lockBadge:destroy(); record.lockBadge = nil end
      if record.editBadge then record.editBadge:destroy(); record.editBadge = nil end
      move:destroy()
      record.move = nil
      return
    end
  end

  if record.spec.resizable and not elementLocked(record) then
    local grip = hafen.ui():widget()
    record.grip = grip
    grip:name("resize-" .. record.instanceId):parent(hud):size(HANDLE, HANDLE)
      :position(point.x - origin.x + math.max(0, box.w - HANDLE),
        point.y - origin.y + math.max(0, box.h - HANDLE))
    grip:on("Draw", function(event)
      local g = event:g()
      g:color(120, 220, 255, 255)
      g:frect(1, 1, HANDLE - 2, HANDLE - 2)
      g:color(10, 35, 60, 255)
      g:rect(2, 2, HANDLE - 4, HANDLE - 4)
    end)
    record.grip = grip
    if record.spec.manage then
      local ok, failure = pcall(function() target:resizable(grip) end)
      if not ok and not record.resizeError then
        record.resizeError = true
        hafen.log():write("cannot arm '" .. record.spec.label .. "' for resizing: " .. tostring(failure))
      end
      if not ok then grip:destroy(); record.grip = nil end
    end
  end
end

arm = function(record)
  local ok, failure = pcall(buildEditor, record)
  if not ok then
    dropEditor(record)
    attempt("cannot create editor for " .. record.spec.label, function() error(failure, 0) end)
  end
end

local function remember(record)
  if record.remembered or not record.spec.remember or not record.target:exists() then return end
  if not record.state.session:character() then return end
  local ok, failure = pcall(function()
    record.target:remember(record.instanceId, record.state.session:store())
    -- Owned placeholders also save their box. Keep the remembered placement,
    -- but discard dimensions saved by earlier, oversized placeholder versions.
    if record.isPreview then
      record.target:size(record.spec.preview.w, record.spec.preview.h)
    end
  end)
  if ok then
    record.remembered = true
  elseif not record.rememberError then
    record.rememberError = true
    hafen.log():write("cannot remember '" .. record.spec.label .. "': " .. tostring(failure))
  end
end

local function addTarget(state, spec, target, index, isPreview)
  if state.byTarget[target] then return end
  -- A region has no usable rectangle until its painter has drawn a frame.
  if target:type() == "Region" then
    local box = target:size()
    if not box or box.w <= 0 or box.h <= 0 then return end
  end
  local suffix = (spec.multiple and index) and ("-" .. index) or ""
  -- Tree order can change when windows open, close or are raised. Never give
  -- an existing record's saved-position name to a different target.
  local baseId = spec.id .. suffix
  local instanceId, serial = baseId, 1
  while state.usedIds[instanceId] do
    serial = serial + 1
    instanceId = baseId .. "-instance-" .. serial
  end
  state.usedIds[instanceId] = true
  local record = {
    state = state,
    spec = spec,
    target = target,
    instanceId = instanceId,
    visibilityKey = (target:title() and ("window:" .. target:title())) or (spec.id .. suffix),
    isPreview = isPreview == true,
    defaultPosition = target:position(),
    defaultSize = target:size(),
  }
  state.byTarget[target] = record
  remember(record)
  record.dragged = target:on("Dragged", function() snapPosition(record) end)
  if spec.resizable then
    record.resized = target:on("Resized", function() enforceSize(record, true) end)
  end
  arm(record)
end

local function centerRecord(record)
  local target = record.target
  if not target:exists() then return end
  local parent, box = target:parent(), target:size()
  local room = record.state.hud:size()
  local screen = record.state.hud:rootPos()
  local origin = parent and parent:rootPos()
  if room and box and origin then
    target:position(math.floor(screen.x + (room.w - box.w) / 2 - origin.x),
      math.floor(screen.y + (room.h - box.h) / 2 - origin.y))
  end
end

local function resetRecord(record)
  local target = record.target
  if not target:exists() then return end
  if record.spec.remember then
    pcall(function() target:remember(nil) end)
    record.remembered = false
  end
  local position, box = record.defaultPosition, record.defaultSize
  if position then target:position(position.x, position.y) end
  if box and record.spec.resizable then target:size(box.w, box.h) end
  remember(record)
end

local function dropRecord(record)
  dropEditor(record)
  if record.dragged then pcall(function() record.dragged:off() end) end
  if record.resized then pcall(function() record.resized:off() end) end
  record.state.usedIds[record.instanceId] = nil
  if record.isPreview and record.target:exists() then record.target:destroy() end
  -- Revert drops the hold but preserves the saved location for the next fight.
  if record.target:exists() and record.target:type() == "Region" then
    pcall(function() record.target:revert() end)
  end
end

sync = function(state)
  if not (state.session:exists() and state.session:character() and state.hud:exists()) then return end
  -- Free saved names before discovering a replacement widget or a new fight.
  for target, record in pairs(state.byTarget) do
    if not target:exists() or (record.spec.enabled and not record.spec.enabled()) then
      dropRecord(record)
      state.byTarget[target] = nil
    end
  end
  for _, spec in pairs(registrations) do
    local ok, matches = true, {}
    if spec.selector and (not spec.enabled or spec.enabled()) then
      ok, matches = pcall(function() return state.session:ui():matchAll(spec.selector) end)
    end
    if ok then
      if spec.preview then
        state.previews = state.previews or {}
        local native = matches[1]
        local box = native and native:size()
        local painted = box and box.w > 0 and box.h > 0
        local active = not spec.enabled or spec.enabled()
        local showPreview = active and unlocked() and not painted
        local preview = state.previews[spec.id]
        if preview and (not showPreview or not preview:exists()) then
          local record = state.byTarget[preview]
          if record then dropRecord(record); state.byTarget[preview] = nil end
          if preview:exists() then preview:destroy() end
          state.previews[spec.id] = nil
          preview = nil
        end
        if showPreview then
          -- A live IP region can temporarily lose its target/box. Release its
          -- saved name before using the edit placeholder under that same name.
          if native and state.byTarget[native] then
            dropRecord(state.byTarget[native]); state.byTarget[native] = nil
          end
          if not preview then
            local room, p = state.hud:size(), spec.preview
            preview = hafen.ui():widget():name("preview-" .. spec.id):parent(state.hud)
              :size(p.w, p.h):position(math.max(0, math.floor(room.w / 2 + p.x)),
                math.max(0, math.floor(room.h / 2 + p.y)))
            state.previews[spec.id] = preview
          end
          matches = {preview}
        end
      end
      if #matches > 0 then
        local limit = spec.multiple and #matches or 1
        for index = 1, limit do
          local target = spec.parentTarget and matches[index]:parent() or matches[index]
          if target then attempt("discover " .. spec.id, function()
            addTarget(state, spec, target, index,
              state.previews and state.previews[spec.id] == target)
          end) end
        end
      end
    elseif not state.selectorErrors[spec.id] then
      state.selectorErrors[spec.id] = true
      hafen.log():write("cannot find '" .. spec.label .. "': " .. tostring(matches))
    end
  end
  -- Kami enumerates real movable objects recursively. Brodgar has no common
  -- DraggableWidget class, so supplement named adapters with real HUD windows
  -- and top-level surfaces, excluding structural/full-screen containers.
  local excluded = {GameUI=true, MapView=true, AlignPanel=true,
    Widget=true, OptWnd=true, Fightsess=true, Region=true, Speedget=true}
  local counts, seen = {}, {}
  local candidates = state.hud:children():list()
  for _, target in ipairs(state.session:ui():matchAll("window")) do
    if target:type() ~= "OptWnd" then candidates[#candidates + 1] = target end
  end
  for _, target in ipairs(candidates) do
    local name, kind = target:name(), target:type()
    local box = target:size()
    if target:exists() and not seen[target] and not excluded[kind] and box and box.w > 0 and box.h > 0
        and not (name and (name:match("^movable%-ui/") or name:match("^whatat%-tracker/"))) then
      seen[target] = true
      local base = name or kind
      counts[base] = (counts[base] or 0) + 1
      local id = "found-" .. base:gsub("[^%w_-]", "-") .. "-" .. counts[base]
      local spec = {id=id, label=name or target:title() or kind, manage=true,
        remember=true, resizable=false, minWidth=1, minHeight=1}
      attempt("discover " .. id, function() addTarget(state, spec, target, nil, false) end)
    end
  end
  for target, record in pairs(state.byTarget) do
    if not target:exists() then
      dropRecord(record)
      state.byTarget[target] = nil
    else
      attempt("edit " .. record.instanceId, function()
        remember(record)
        local box = target:size()
        if unlocked() and boxShown(record) and box and box.w > 0 and box.h > 0 then
          arm(record)
        else dropEditor(record) end
      end)
    end
  end
end

local function applyMode()
  refreshLockButton()
  for _, state in pairs(sessions) do attempt("scan", function() sync(state) end) end
end

local function setUnlocked(value)
  lockOption:value(value ~= true)
  applyMode()
end

local function recordsForCurrentSession()
  local session = hafen.session():current()
  local state = session and sessions[session] or nil
  local records = {}
  if state then
    attempt("refresh widget list", function() sync(state) end)
    for _, record in pairs(state.byTarget) do
      if record.target:exists() then records[#records + 1] = record end
    end
  end
  table.sort(records, function(a, b) return a.instanceId < b.instanceId end)
  return records
end

-- This command belongs to the editor, so widget diagnostics are available
-- even when the separate What At snapshot addon is disabled.
local function scanWidgets()
  closeWindow(debugWindow)
  debugWindow = nil
  local session = hafen.session():current()
  local lines, count = {}, 0
  local ok, failure = pcall(function()
    if not (session and session:exists()) then error("No active session. Enter the world first.", 0) end
    session:ui():root():walk(function(node, depth)
      count = count + 1
      local place, box = node:rootPos(), node:size()
      lines[#lines + 1] = string.format("%d %s%s name=%s visible=%s at=%s size=%s",
        count, string.rep(" ", math.min(depth or 0, 12)), tostring(node:type()),
        tostring(node:name()), tostring(node:visible()),
        place and (place.x .. "," .. place.y) or "?",
        box and (box.w .. "x" .. box.h) or "?")
    end)
  end)
  if not ok then lines[#lines + 1] = "Scan failed: " .. tostring(failure) end
  local win = hafen.ui():window():name("widget-debug"):title("Widget Scan"):position(40, 90)
  debugWindow = win
  hafen.ui():label():parent(win):position(0, 0):text(
    "Session widgets: " .. count .. " (includes hidden widgets)")
  local scroll = hafen.ui():scroll():parent(win):position(0, 28):size(720, 390)
  local content = hafen.ui():widget():parent(scroll):position(0, 0)
    :size(980, math.max(24, math.min(#lines + 1, 251) * 20))
  for index = 1, math.min(#lines, 250) do
    local line = lines[index]
    local display = copyPages(line)[1]
    if #display < #line then display = display .. "..." end
    hafen.ui():label():parent(content):position(0, (index - 1) * 20):text(display)
  end
  if count > 250 then
    hafen.ui():label():parent(content):position(0, 250 * 20)
      :text("Showing first 250 of " .. count .. " widgets. Write to log for all entries.")
  end
  local report = "Widget Scan\nSession widgets: " .. count .. " (includes hidden widgets)\n"
    .. table.concat(lines, "\n")
  local copy = hafen.ui():button():parent(win):position(0, 426):size(100):text("Copy...")
    :tooltip("Copy the scan in short pages with Ctrl+A, Ctrl+C")
  local writeLog = hafen.ui():button():parent(win):position(110, 426):size(120):text("Write to log")
    :tooltip("Write the full scan to the client terminal output")
  local pages, page = copyPages(report), 1
  local copyField = hafen.ui():entry():name("widget-debug-copy"):parent(win)
    :position(240, 426):size(480):value(""):visible(false)
  local previous = hafen.ui():button():parent(win):position(0, 462):size(100)
    :text("Previous"):visible(false)
  local nextPage = hafen.ui():button():parent(win):position(110, 462):size(100)
    :text("Next"):visible(false)
  local pageLabel = hafen.ui():label():parent(win):position(220, 466):text(""):visible(false)
  local copyHelp = hafen.ui():label():parent(win):position(0, 498)
    :text("Click the field, Ctrl+A, Ctrl+C; paste each page in order, then click Next."):visible(false)
  local function showPage()
    if not win:exists() then return end
    copyField:value(pages[page])
    pageLabel:text("Page " .. page .. " / " .. #pages)
  end
  previous:on("Pressed", function() hafen.timer():after(0, function()
    page = math.max(1, page - 1); showPage()
  end) end)
  nextPage:on("Pressed", function() hafen.timer():after(0, function()
    page = math.min(#pages, page + 1); showPage()
  end) end)
  copy:on("Pressed", function() hafen.timer():after(0, function()
    if not win:exists() then return end
    copyField:visible(true)
    copyHelp:visible(true)
    previous:visible(true)
    nextPage:visible(true)
    pageLabel:visible(true)
    showPage()
    win:pack()
  end) end)
  writeLog:on("Pressed", function() hafen.timer():after(0, function()
    if not win:exists() then return end
    local ok = pcall(function()
      hafen.log():write("----- WIDGET SCAN BEGIN -----\n" .. report
        .. "\n----- WIDGET SCAN END -----")
    end)
    writeLog:text(ok and "Written!" or "Log failed")
    hafen.timer():after(2, function()
      if writeLog:exists() then writeLog:text("Write to log") end
    end)
  end) end)
  win:pack()
  win:on("Close", function() hafen.timer():after(0, function()
    closeWindow(win)
    if debugWindow == win then debugWindow = nil end
  end) end)
end

openElementEditor = function(record)
  closeWindow(editWindow)
  if not record.target:exists() then return end
  local box = record.target:size()
  if not box then return end
  local win = hafen.ui():window():name("widget-edit"):title("Edit " .. record.spec.label):position(410, 210)
  editWindow = win
  hafen.ui():label():parent(win):position(0, 0):text("Width (px)")
  local width = hafen.ui():entry():parent(win):position(100, 0):size(90):value(tostring(box.w))
  hafen.ui():label():parent(win):position(0, 34):text("Height (px)")
  local height = hafen.ui():entry():parent(win):position(100, 34):size(90):value(tostring(box.h))
  local status = hafen.ui():label():parent(win):position(0, 72)
    :text(record.spec.resizable and "" or "This widget does not expose resizing.")
  local apply = hafen.ui():button():parent(win):position(0, 100):size(100):text("Apply size")
  apply:on("Pressed", function()
    hafen.timer():after(0, function()
      if not record.target:exists() then status:text("Widget closed."); return end
      if not record.spec.resizable then status:text("Resizing unavailable for this widget."); return end
      local w, h = tonumber(width:value()), tonumber(height:value())
      if not (validNumber(w) and validNumber(h)) then
        status:text("Enter positive width and height.")
        return
      end
      w, h = math.floor(w), math.floor(h)
      w, h = math.max(record.spec.minWidth, w), math.max(record.spec.minHeight, h)
      local ok, failure = pcall(function() record.target:size(w, h) end)
      status:text(ok and ("Requested " .. w .. " x " .. h .. " px") or tostring(failure))
    end)
  end)
  hafen.ui():label():parent(win):position(0, 140)
    :text(record.target:type() == "Region" and "Drawing order is controlled by the client." or
      "This editor does not change front/back order.")
  win:pack():remember("edit-element-window")
  win:on("Close", function() hafen.timer():after(0, function()
    closeWindow(win)
    if editWindow == win then editWindow = nil end
  end) end)
end

local function closeList()
  local old = listWindow
  listWindow = nil
  closeWindow(old)
end

local function openList()
  closeList()
  local win = hafen.ui():window():name("widget-list"):title("HUD widgets"):position(390, 180)
  listWindow = win
  local scroll = hafen.ui():scroll():parent(win):position(0, 0):size(330, 360)
  local content = hafen.ui():widget():parent(scroll):position(0, 0):size(440, 24)
  local records = recordsForCurrentSession()
  if #records == 0 then
    hafen.ui():label():parent(content):position(0, 0):text("No movable widgets discovered yet.")
  end
  scroll:size(460, 360)
  content:size(440, math.max(24, #records * 32))
  for index, record in ipairs(records) do
    local selected = record
    local y = (index - 1) * 32
    hafen.ui():label():parent(content):position(0, y + 4):text(selected.spec.label)
    local center = hafen.ui():button():parent(content):position(230, y):size(86):text("Center")
    center:on("Pressed", function()
      hafen.timer():after(0, function() centerRecord(selected) end)
    end)
    local reset = hafen.ui():button():parent(content):position(320, y):size(110):text("Reset")
    reset:on("Pressed", function()
      hafen.timer():after(0, function() resetRecord(selected) end)
    end)
  end
  win:pack():remember("widget-list")
  win:on("Close", function() hafen.timer():after(0, closeList) end)
end

local function closeEditor()
  closeList()
  closeWindow(visibilityWindow)
  visibilityWindow = nil
  closeWindow(editWindow)
  editWindow = nil
  local old = editorWindow
  editorWindow, lockButton = nil, nil
  closeWindow(old)
end

local function openVisibilityList()
  closeWindow(visibilityWindow)
  local win = hafen.ui():window():name("box-list"):title("Blue boxes"):position(390, 180)
  visibilityWindow = win
  hafen.ui():label():parent(win):position(0, 0):text("Show edit boxes (does not hide the widgets themselves)")
  local scroll = hafen.ui():scroll():parent(win):position(0, 28):size(460, 360)
  local records = recordsForCurrentSession()
  local content = hafen.ui():widget():parent(scroll):position(0, 0):size(440, math.max(24, #records * 30))
  local counts = {}
  for _, record in ipairs(records) do
    counts[record.spec.label] = (counts[record.spec.label] or 0) + 1
  end
  local indices = {}
  for index, record in ipairs(records) do
    local selected = record
    local label = selected.spec.label
    indices[label] = (indices[label] or 0) + 1
    if counts[label] > 1 then label = label .. " (" .. indices[label] .. ")" end
    local check = hafen.ui():check():parent(content):position(0, (index - 1) * 30)
      :text(label):value(boxShown(selected))
    check:on("Changed", function(show)
      -- Owned checkbox Changed supplies the boolean directly. Native borrowed
      -- controls use event objects; this checkbox was built by this addon.
      hafen.timer():after(0, function()
        selected.state.boxVisibility[selected.visibilityKey] = show
        if show and unlocked() then arm(selected) else dropEditor(selected) end
      end)
    end)
  end
  if #records == 0 then
    hafen.ui():label():parent(content):position(0, 0):text("No widgets discovered yet.")
  end
  win:pack():remember("blue-box-list")
  win:on("Close", function()
    hafen.timer():after(0, function()
      closeWindow(win)
      if visibilityWindow == win then visibilityWindow = nil end
    end)
  end)
end

local function lockFromEditor()
  setUnlocked(false)
  closeEditor()
  if optionsWindow and optionsWindow:exists() then optionsWindow:visible(true) end
end

local function openEditor()
  closeEditor()
  local session = hafen.session():current()
  local state = session and sessions[session]
  if not state then return end
  local room = state.hud:size()
  -- Plain panel: its background drags it, while controls retain their clicks.
  local win = hafen.ui():widget():name("editor"):parent(state.hud):size(270, 220)
    :position(math.max(0, math.floor((room.w - 270) / 2)), math.max(0, math.floor((room.h - 220) / 2)))
  editorWindow = win
  -- New combat handles must not cover the editor's lock and option controls.
  win:z(5)
  win:on("Draw", function(event)
    local g = event:g()
    g:color(10, 16, 22, 245); g:frect(0, 0, event:w(), event:h())
    g:color(86, 188, 255, 255); g:rect(0, 0, event:w(), event:h())
  end)
  local drag = hafen.ui():widget():name("editor-drag"):parent(win):position(0, 0):size(270, 220)
  drag:on("Draw", function(event)
    local g = event:g()
    g:color(210, 220, 235, 255)
    g:atext("GUI layout", event:w() / 2, 14, 0.5, 0.5)
  end)
  win:draggable(drag)
  -- Columns always left-align their children. Lay out a plain surface instead
  -- so every control, including labels and checkboxes, has the same centre.
  local root = hafen.ui():widget():parent(win):position(12, 32)
  local function layout()
    if not win:exists() then return end
    local children = root:children():list()
    local width, height = 246, 0
    for _, child in ipairs(children) do width = math.max(width, child:size().w) end
    for _, child in ipairs(children) do
      local box = child:size()
      child:position(math.floor((width - box.w) / 2), height)
      height = height + box.h + 8
    end
    height = math.max(0, height - 8)
    root:size(width, height)
    win:size(width + 24, height + 44)
    drag:size(width + 24, height + 44)
  end
  lockButton = hafen.ui():button():parent(root):size(240):text(lockText())
  lockButton:on("Pressed", function() hafen.timer():after(0, lockFromEditor) end)
  hafen.ui():check():parent(root):text("Show and snap to grid"):bind(gridOption)
  local sizeLabel = hafen.ui():label():parent(root):text("Grid size: " .. gridSizeOption:value() .. " px")
  local sizeSlider = hafen.ui():slider():parent(root):size(190):bind(gridSizeOption)
  sizeSlider:on("Changed", function()
    sizeLabel:text("Grid size: " .. tostring(gridSizeOption:value()) .. " px")
    layout()
  end)
  hafen.ui():check():parent(root):text("Snap to screen center line"):bind(centerOption)
  hafen.ui():check():parent(root):text("Draw combat GUI"):bind(combatOption)
    :tooltip("Show all eight combat edit boxes, including placeholders outside combat")
  local widgets = hafen.ui():button():parent(root):size(190):text("Center / reset widgets...")
  widgets:on("Pressed", function() hafen.timer():after(0, openList) end)
  local boxes = hafen.ui():button():parent(root):size(190):text("Show / hide blue boxes...")
  boxes:on("Pressed", function() hafen.timer():after(0, openVisibilityList) end)
  local debug = hafen.ui():button():parent(root):size(190):text("Scan widgets...")
  debug:on("Pressed", function() hafen.timer():after(0, scanWidgets) end)
  layout()
  win:position(math.max(0, math.floor((room.w - win:size().w) / 2)),
    math.max(0, math.floor((room.h - win:size().h) / 2)))
  win:remember("gui-editor", session:store())
end

local function findWindow(node)
  local current = node
  while current do
    if current:role() == "window" or current:type() == "OptWnd" then return current end
    current = current:parent()
  end
  return nil
end

local function drawGrid(state, event)
  if not unlocked() then return end
  local g, width, height = event:g(), event:w(), event:h()
  if gridOption:value() then
    local step = math.max(2, gridSizeOption:value())
    g:color(86, 188, 255, 80)
    for x = step, width - 1, step do g:frect(x, 0, 1, height) end
    for y = step, height - 1, step do g:frect(0, y, width, 1) end
  end
  if centerOption:value() then
    g:color(255, 221, 64, 150)
    g:frect(math.floor(width / 2), 0, 1, height)
  end
end

attach = function(session)
  if not (session:exists() and session:character()) then return end
  if sessions[session] then return end
  local hud = session:ui():match("@GameUI")
  if not hud then return end
  -- The identity and GameUI may arrive before per-character storage does.
  -- Leave this session unattached until both variables can be acquired.
  local ready, visibility, locks = pcall(function()
    local store = session:store()
    return store:var("blue-box-visibility"), store:var("element-locks")
  end)
  if not ready then
    if tostring(visibility):find("no character yet", 1, true) then return end
    error(visibility, 0)
  end
  local state = {session = session, hud = hud, byTarget = {}, usedIds = {}, selectorErrors = {},
    boxVisibility = visibility, elementLocks = locks}
  sessions[session] = state
  local room = hud:size()
  local grid = hafen.ui():widget():name("grid"):parent(hud):position(0, 0):size(room.w, room.h)
  grid:on("Draw", function(event) drawGrid(state, event) end)
  grid:on("Update", function()
    if hud:exists() and grid:exists() then
      local size = hud:size()
      if size then grid:size(size.w, size.h) end
    end
  end)
  state.grid = grid
  attempt("initial discovery", function() sync(state) end)
end

local function detach(session)
  local state = sessions[session]
  if not state then return end
  for _, record in pairs(state.byTarget) do dropRecord(record) end
  if state.grid and state.grid:exists() then state.grid:destroy() end
  sessions[session] = nil
end

-- The menu page, rebuilt whenever Options > AddOns > Movable UI is opened.
addonOptions:panel(function(root)
  root:gap(6)
  hafen.ui():label():parent(root):text("HUD layout editor")
  hafen.ui():label():parent(root):text("Includes HUD, vital bars, speed, quests and notifications.")
  lockButton = hafen.ui():button():parent(root):size(180):text(lockText())
    :tooltip("turn the blue movement and resize boxes on or off")
  lockButton:on("Pressed", function()
    optionsWindow = findWindow(root)
    hafen.timer():after(0, function()
      if unlocked() then
        setUnlocked(false)
      else
        setUnlocked(true)
        if optionsWindow and optionsWindow:exists() then optionsWindow:visible(false) end
        openEditor()
      end
    end)
  end)
  hafen.ui():label():parent(root):text("Unlock to open the compact HUD editor.")
  hafen.ui():check():parent(root):text("Use movable combat interface"):bind(combatOption)
    :tooltip("Fix native combat regions on screen; unlock to move each part")
  hafen.ui():label():parent(root):text("Guide: addons/movable-ui/README.md")
end)

lockOption:on("Changed", function() hafen.timer():after(0, applyMode) end)
gridOption:on("Changed", function() hafen.timer():after(0, applyMode) end)
gridSizeOption:on("Changed", function() hafen.timer():after(0, applyMode) end)
centerOption:on("Changed", function() hafen.timer():after(0, applyMode) end)
combatOption:on("Changed", function()
  hafen.timer():after(0, function()
    for _, callback in ipairs(combatChanged) do
      attempt("combat option", function() callback(combatOption:value() == true) end)
    end
    applyMode()
  end)
end)

hafen.event():on("SessionEnteredWorld", function(session) attach(session) end)
hafen.event():on("SessionRemoved", function(session) detach(session) end)

-- Widgets may stream in or be rebuilt after entering the world.
hafen.timer():every(0.25, function()
  -- Addons can load after the world-enter event. Recover current sessions and
  -- HUDs here so startup order never prevents discovery.
  for _, session in ipairs(hafen.session():list()) do
    local state = sessions[session]
    if state and not state.hud:exists() then detach(session) end
    if not sessions[session] then attempt("attach", function() attach(session) end) end
  end
  for _, state in pairs(sessions) do attempt("scan", function() sync(state) end) end
  if unlocked() then
    if optionsWindow and optionsWindow:exists() then optionsWindow:visible(false) end
    if not (editorWindow and editorWindow:exists()) then openEditor() end
  elseif editorWindow then
    closeEditor()
    if optionsWindow and optionsWindow:exists() then optionsWindow:visible(true) end
  end
end)

hafen.event():on("Disable", function()
  closeEditor()
  closeWindow(debugWindow)
  debugWindow = nil
  if optionsWindow and optionsWindow:exists() then optionsWindow:visible(true) end
  for session in pairs(sessions) do detach(session) end
end)

hafen.console():on("widgetscan", function() hafen.timer():after(0, scanWidgets) end)

-- Shared only within this addon's Lua environment; the remaining manifest
-- files install the built-in HUD modules after the editor has initialized.
MoveableUI = {
  register = register,
  unlocked = unlocked,
  setUnlocked = setUnlocked,
  combatEnabled = function() return combatOption:value() == true end,
  onCombatChanged = function(callback) combatChanged[#combatChanged + 1] = callback end,
}
hafen.client():addons():export(MoveableUI)
