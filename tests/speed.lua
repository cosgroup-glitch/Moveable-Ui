-- Native speed lifecycle checks against the real hud.lua module.
local registrations, events, hosts = {}, {}, {}
local tick
MoveableUI={register=function(spec) registrations[spec.id]=spec end}
local hud={exists=function() return true end, size=function() return {w=1000,h=700} end,
  rootPos=function() return {x=0,y=0} end}
local original={rootPos=function() return {x=20,y=30} end}
local function speed()
  local item={alive=true, owner=original, point={x=5,y=10}, box={w=120,h=25}}
  function item:exists() return self.alive end
  function item:size() return self.box end
  function item:parent(...)
    if select("#",...) == 0 then return self.owner end
    self.owner=(...) or original
    self.point=(...) and {x=0,y=0} or {x=5,y=10}
    return self
  end
  function item:position(x,y)
    if x then self.point={x=x,y=y}; return self end
    return self.point
  end
  function item:rootPos()
    local root=self.owner:rootPos()
    return {x=root.x+self.point.x,y=root.y+self.point.y}
  end
  function item:destroy() error("native Speedget must never be destroyed") end
  return item
end
local native=speed()
local ui={match=function(_,selector)
  if selector == "@GameUI" then return hud end
  if selector == "@Speedget" then return native end
end}
local session={exists=function() return true end,character=function() return "test" end,
  ui=function() return ui end}
local function host()
  local item={alive=true,point={x=0,y=0}}
  function item:name(value) self.id=value; return self end
  function item:parent(value) self.owner=value; return self end
  function item:size(w,h)
    if w then self.box={w=w,h=h}; return self end
    return self.box
  end
  function item:position(x,y) self.point={x=x,y=y}; return self end
  function item:rootPos() return self.point end
  function item:exists() return self.alive end
  function item:destroy() self.alive=false end
  hosts[#hosts+1]=item
  return item
end
hafen={
  ui=function() return {widget=host} end,
  session=function() return {list=function() return {session} end} end,
  timer=function() return {every=function(_,_,fn) tick=fn end} end,
  event=function() return {on=function(_,name,fn) events[name]=fn end} end,
  log=function() return {write=function(_,message) error(message) end} end,
}
assert(loadfile("hud.lua"))()
assert(registrations["speed-selector"].selector == "[name=movable-ui/speed]")
tick()
local first=hosts[1]
assert(native:parent() == first and first.owner == hud)
assert(first.point.x == 25 and first.point.y == 40, "host starts at native screen location")
assert(native.point.x == 0 and native.point.y == 0)
first:position(450,300)
tick()
assert(native:rootPos().x == 450 and native:rootPos().y == 300,
  "moving the container must move the real speed icons")
assert(#hosts == 1, "polling must retain the existing native widget and host")
native.box={w=140,h=25}
tick()
assert(first.box.w == 140, "host follows native artwork size")
local old=native
native=speed()
tick()
assert(not first.alive and old.owner == original and old.alive)
assert(native.owner == hosts[2], "rebuilt speed widget must get its own host")
events.Disable()
assert(native.owner == original and native.alive and not hosts[2].alive)
assert(native.point.x == 5 and native.point.y == 10, "disable restores native placement")
print("Speed regression checks passed")
