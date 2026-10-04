-- Exercise the real editor's discovery and lifecycle with a small API double.
-- The native painter and input handling still require an in-game check.
local options, failures, saved = {}, {}, {}
local forbiddenWrites = 0
local function option(id)
  if options[id] then return options[id] end
  local item = {}
  function item:default(value) self.current = value; return self end
  function item:range() return self end
  function item:add() return self end
  function item:on() return self end
  function item:value(value)
    if value ~= nil then self.current = value; return self end
    return self.current
  end
  options[id] = item
  return item
end
local addon = {boolean=function(_, id) return option(id) end,
  number=function(_, id) return option(id) end, panel=function() end}
local client = {options=function() return {addon=function() return addon end} end,
  addons=function() return {export=function() end} end}
local bus = {on=function() end}
hafen = {
  client=function() return client end,
  timer=function() return {after=function() end, every=function() end} end,
  event=function() return bus end, console=function() return bus end,
  log=function() return {write=function(_, message) failures[#failures+1] = message end} end,
}
local file = assert(io.open("main.lua", "r"))
local source = file:read("*a"); file:close()
local editor = assert(load(source ..
  "\nreturn {sync=sync, dropRecord=dropRecord, resetRecord=resetRecord}"))()
assert(loadfile("combat.lua"))()
local targets = {}
local hud = {exists=function() return true end}
function hud:size() return {w=1000,h=700} end
function hud:rootPos() return {x=0,y=0} end
function hud:children() return {list=function() return targets end} end
local function surface()
  local item={alive=true, box={w=10,h=20}, point={x=0,y=0}, handlers={}}
  function item:exists() return self.alive end
  function item:destroy() self.alive=false; self.key=nil end
  function item:name(value)
    if value then self.widgetName="movable-ui/" .. value; return self end
    return self.widgetName
  end
  function item:type() return "AddonWidget" end
  function item:title() return nil end
  function item:parent(value)
    if value then self.owner=value; return self end
    return self.owner
  end
  function item:rootPos() return self.point end
  function item:draggable(handle) self.handle=handle; return self end
  function item:remember(key)
    self.key=key
    if saved[key] then self.point={x=saved[key].x,y=saved[key].y} end
    if saved[key] and saved[key].size then self.box=saved[key].size end
    return self
  end
  function item:text() return self end
  function item:tooltip() return self end
  function item:visible(value) self.shown=value; return self end
  function item:size(w,h)
    if w then self.box={w=w,h=h or self.box.h}; return self end
    return self.box
  end
  function item:position(x,y)
    if x then
      self.point={x=x,y=y}
      if self.key then saved[self.key]={x=x,y=y} end
      return self
    end
    return self.point
  end
  function item:on(event,fn) self.handlers[event]=fn; return self end
  function item:off() end
  return item
end
hafen.ui=function() return {widget=surface, button=surface,
  mouse=function() return {x=function() return 0 end,y=function() return 0 end} end} end
local ui = {}
function ui:matchAll(selector)
  local found = {}
  for _, target in ipairs(targets) do
    if target.alive and target.roleName == selector then found[#found+1] = target end
  end
  return found
end
local session = {exists=function() return true end, character=function() return "test" end,
  ui=function() return ui end, store=function() return {} end}
local state = {session=session, hud=hud, byTarget={}, usedIds={}, selectorErrors={},
  boxVisibility={}, elementLocks={}}
local function region(role, width, height)
  local target = {roleName=role, alive=true, box={w=width, h=height}, point={x=120,y=200}}
  function target:exists() return self.alive end
  function target:type() return "Region" end
  function target:name() return nil end
  function target:title() return nil end
  function target:parent() return hud end
  function target:rootPos() return self.point end
  function target:size(...)
    if select("#", ...) > 0 then forbiddenWrites=forbiddenWrites+1; error("region size write") end
    return self.box
  end
  function target:position(x,y)
    if x == nil then return self.point end
    self.point={x=x,y=y}; self.held=true
    if self.key then saved[self.key]={x=x,y=y} end
    return self
  end
  function target:remember(key)
    if key == nil then saved[self.key]=nil; self.key=nil; return self end
    self.key=key; self.held=true
    if saved[key] then self.point={x=saved[key].x,y=saved[key].y} end
    return self
  end
  function target:on() return {off=function() end} end
  function target:draggable(handle) self.handle=handle; return self end
  function target:resizable() forbiddenWrites=forbiddenWrites+1; error("region resize binding") end
  function target:revert() self.held=false; self.key=nil; self.reverted=true; return self end
  return target
end
local first = region("fight.action", 0, 0)
local unrelated = region("other.role", 50, 50)
targets={first,unrelated}
editor.sync(state)
assert(next(state.byTarget) == nil, "disabled combat must not be auto-discovered")
options["movable-combat"]:value(true)
editor.sync(state)
assert(next(state.byTarget) == nil, "wait for the first painted frame")
first.box={w=250,h=50}
editor.sync(state)
assert(state.byTarget[first].instanceId == "combat-interface")
first:position(420,360)
first.alive=false
local second=region("fight.action",250,50)
targets={second,unrelated}
editor.sync(state)
assert(state.byTarget[first] == nil)
assert(state.byTarget[second].instanceId == "combat-interface", "new fight must reuse saved ID")
assert(second.point.x == 420 and second.point.y == 360, "new fight restores layout")
options["movable-combat"]:value(false)
editor.sync(state)
assert(next(state.byTarget) == nil and second.reverted and not second.held)
assert(saved["combat-interface"].x == 420, "toggle must preserve saved placement")
options["movable-combat"]:value(true)
editor.sync(state)
assert(second.held and second.key == "combat-interface")
local ip=region("fight.ip.mine",0,0)
targets={second,ip}
editor.sync(state)
assert(not state.byTarget[ip], "IP without a target has no editable box")
ip.box={w=40,h=15}
editor.sync(state)
assert(state.byTarget[ip].instanceId == "combat-ip-mine")
options["gui-lock"]:value(false)
editor.sync(state)
local handle=assert(second.handle, "unlock must arm the native move handle")
assert(handle.alive and not state.byTarget[second].grip, "region must have no resize grip")
local count=0
for _ in pairs(state.byTarget) do count=count+1 end
assert(count == 8, "unlock must draw all eight combat regions or placeholders")
ip.box={w=0,h=0}
state.byTarget[ip].move.handlers.Update()
assert(state.byTarget[ip].move.shown == false, "zero-sized IP must hide its handle")
editor.sync(state)
assert(not ip.handle and not state.byTarget[ip])
local preview=assert(state.previews["combat-ip-mine"])
assert(preview.handle, "missing IP must have an editable placeholder")
preview:position(350,210)
ip.box={w=40,h=15}
editor.sync(state)
assert(ip.handle, "IP handle returns when the target returns")
assert(not preview.alive and not state.previews["combat-ip-mine"])
assert(ip.point.x == 350 and ip.point.y == 210, "real region must use the preview's placement")
options["gui-lock"]:value(true)
editor.sync(state)
assert(not second.handle and not handle.alive and second.held,
  "locking disarms clicks while preserving fixed placement")
for _, preview in pairs(state.previews) do assert(not preview:exists(), "lock must remove previews") end
editor.resetRecord(state.byTarget[ip])
assert(ip.held, "reset rebinds remembering without writing region size")
for _, record in pairs(state.byTarget) do editor.dropRecord(record) end
assert(not second.held and not ip.held, "teardown must release all live regions")
assert(saved["combat-interface"].x == 420)
-- No fight at all: all eight editable boxes must still appear.
targets={unrelated}
second.alive=false; ip.alive=false
saved["combat-ip-mine"]={x=350,y=210,size={w=140,h=24}}
options["gui-lock"]:value(false)
editor.sync(state)
count=0
for _, record in pairs(state.byTarget) do
  assert(record.isPreview and record.target.handle)
  count=count+1
end
assert(count == 8, "combat editor must work outside combat")
local corrected=state.previews["combat-ip-mine"]
assert(corrected.box.w == 39 and corrected.box.h == 28,
  "old saved preview dimensions must not override the native-sized box")
assert(corrected.point.x == 350 and corrected.point.y == 210,
  "correcting dimensions must retain the saved placement")
options["movable-combat"]:value(false)
editor.sync(state)
assert(next(state.byTarget) == nil, "checkbox off must remove every combat edit box")
assert(#failures == 0, table.concat(failures, "\n"))
assert(forbiddenWrites == 0, "regions must never receive size writes or resize bindings")
print("Region regression checks passed")
