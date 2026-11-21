-- TwizHeal 1.27.0: the party window as a cross (tank top, 3 dps middle, healer bottom)
local f = io.open(REPO .. "/tools/wowsim/healrules.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("SIM.Advance%(0.3%); L%(\"1 tank 90%%") - 1)
local rest = [==[
local NS = TwizHeal
local L = function(s) SIM.log[#SIM.log + 1] = s end
units.party3 = { name = "Mage", class = "MAGE", hp = 900, max = 900 }
units.party4 = { name = "Hunter", class = "HUNTER", hp = 1000, max = 1000 }
local function where()
  local t = {}
  for i = 1, 5 do local b = _G["TwizHealBar" .. i]; t[#t + 1] = (units[b:GetAttribute("unit")] and units[b:GetAttribute("unit")].name or b:GetAttribute("unit")) .. "=" .. tostring(b.slot) end
  return table.concat(t, " ")
end
SIM.Advance(0.3)
L("no roles: " .. where())
assert(TwizHealBar1.slot == "top" and TwizHealBar5.slot == "bottom" and TwizHealBar3.slot == "midC")
local roles = { player = "HEALER", party1 = "DAMAGER", party2 = "DAMAGER", party3 = "TANK", party4 = "DAMAGER" }
UnitGroupRolesAssigned = function(u) return roles[u] or "NONE" end
SIM.Advance(0.3)
L("roles: " .. where())
assert(TwizHealBar4.slot == "top" and TwizHealBar1.slot == "bottom")
assert(TwizHealBar2.slot == "midL" and TwizHealBar3.slot == "midC" and TwizHealBar5.slot == "midR")
local _, _, _, x, y = TwizHealBar4:GetPoint()
L(("tank bar at x=%s y=%s, window %s x %s"):format(tostring(x), tostring(y), tostring(TwizHealFrame and TwizHealFrame:GetWidth()), tostring(TwizHealFrame and TwizHealFrame:GetHeight())))
]==]
assert(loadstring(src .. "\n" .. rest))()
