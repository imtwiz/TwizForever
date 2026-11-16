-- TwizQuest: the sell/repair stop goes away after a vendor visit (bags still full = not junk) or a right-click
local f = io.open(REPO .. "/tools/wowsim/quest.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("%-%- 1%) fresh plan") - 1)
assert(loadstring(src))()
local ns = TwizQuest
local L = function(s) SIM.log[#SIM.log + 1] = s end
for bag = 0, 4 do for slot = 1, 16 do if not SIM.bags[bag .. ":" .. slot] then SIM.bags[bag .. ":" .. slot] = { id = 9999, count = 1 } end end end
SIM.items[9999] = { name = "Jar of Snow", vendor = 0 }
local function first() local r = ns._plan() and ns._plan().route return r and r[1] and (r[1].kind or tostring(r[1].role)) .. " " .. (r[1].q and r[1].q.name or "") or "none" end
local function hasService() for _, s in ipairs(ns._plan().route) do if s.kind == "service" then return true end end return false end
ns.Replan(); SIM.Advance(10); L("bags full: first step = " .. first() .. ", service in route: " .. tostring(hasService()))
SIM.Fire("MERCHANT_CLOSED"); ns.Replan(); SIM.Advance(10)
L("after a vendor visit, bags still full: service in route: " .. tostring(hasService()))
SIM.Advance(1300); ns.Replan(); SIM.Advance(10)
L("21 minutes later: service back: " .. tostring(hasService()))
ns.DismissService(); ns.Replan(); SIM.Advance(10)
L("right-clicked: service in route: " .. tostring(hasService()) .. ", first step = " .. first())
