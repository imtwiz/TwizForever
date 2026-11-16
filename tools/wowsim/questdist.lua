-- TwizQuest: distance to a kill step = nearest spawn, or "here" when one of its mobs is in view
local f = io.open(REPO .. "/tools/wowsim/quest.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("%-%- 1%) fresh plan") - 1)
assert(loadstring(src))()
local ns = TwizQuest
local L = function(s) SIM.log[#SIM.log + 1] = s end
ns.Replan(); SIM.Advance(12)
local st
for _, s in ipairs(ns._plan().route) do if s.role == 2 and s.mobNames then st = s; break end end
L("kill step: " .. tostring(st and st.text) .. " | spawn points kept: " .. tostring(st and st.points and #st.points))
local p = st.points[#st.points]
local center = ns.Dist(p.x, p.y, st.x, st.y)
L(("standing on a far spawn: center %d yd away, live distance %d yd"):format(center, ns.LiveDistance(st, p.x, p.y)))
local name = next(st.mobNames)
UnitName = function(u) if u == "nameplate3" then return name end return u == "player" and "Kitty" or nil end
UnitExists = function(u) return u == "player" or u == "nameplate3" end
UnitIsDead = function() return false end
L(("a %s in view, 900 yd from any spawn: live distance %d"):format(name, ns.LiveDistance(st, p.x + 900, p.y)))
