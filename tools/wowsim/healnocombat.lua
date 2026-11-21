-- TwizHeal 1.17: no heal above 90% in combat (mouse blockers + no-combat key macro)
local f = io.open(REPO .. "/tools/wowsim/healrules.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("SIM.Advance%(0.3%); L%(\"1 tank 90%%") - 1)
local rest = [==[
local NS = TwizHeal
local L = function(s) SIM.log[#SIM.log + 1] = s end
C_Spell.GetSpellCooldown = function() return { startTime = 0, duration = 0 } end
units.party1.hp = 1900; SIM.hots.party1 = nil; NS.moving = false; TwizHeal.hoverUnit = nil
SIM.Advance(0.3)
local key = tostring(TwizHealButton:GetAttribute("macrotext1"))
L("key (no hover): " .. key:gsub("\n", " || "))
assert(not key:find("%[combat%]") and not key:find("combat,"), "key must not heal in combat")
local bar = tostring(TwizHealBar1:GetAttribute("healmacro"))
L("bar1 heal: " .. bar:gsub("\n", " || "))
assert(bar:find("%[combat%]") or bar:find("combat,"), "bar keeps its combat heal")
local b = TwizHealBar1
assert(b.blockFill and b.blockTop, "blockers built")
L("blockers out of combat shown: " .. tostring(b.blockFill:IsShown()) .. "/" .. tostring(b.blockTop:IsShown()))
SIM.Fire("PLAYER_REGEN_DISABLED")
L("blockers in combat shown: " .. tostring(b.blockFill:IsShown()) .. "/" .. tostring(b.blockTop:IsShown()))
assert(b.blockFill:IsShown() and b.blockTop:IsShown())
SIM.Fire("PLAYER_REGEN_ENABLED")
assert(not b.blockFill:IsShown() and not b.blockTop:IsShown())
L("blockers after combat hidden: ok")
-- 1.17.1: the whole bar is clickable under 90%, blocked at 90%+ (guard bar via a step curve)
L("guard in use (no curve API in sim -> fallback): " .. tostring(b.useGuard))
units.party1.hp = 1900; SIM.Advance(0.3)   -- 95% (readable)
L("tank 95% guard value: " .. tostring(TwizHealBar2.guard:GetValue()))
assert(TwizHealBar2.guard:GetValue() == 1)
units.party1.hp = 1700; SIM.Advance(0.3)   -- 85%
L("tank 85% guard value: " .. tostring(TwizHealBar2.guard:GetValue()))
assert(TwizHealBar2.guard:GetValue() == 0)
-- curve API present: hidden health goes through the step curve
local pts
C_CurveUtil = C_CurveUtil or {}
C_CurveUtil.CreateCurve = function() pts = {}; return { SetType = function() end, AddPoint = function(_, x, y) pts[#pts + 1] = { x, y } end } end
Enum = Enum or {}; Enum.LuaCurveType = Enum.LuaCurveType or { Step = 2, Linear = 0 }
local realPct = UnitHealthPercent
UnitHealthPercent = function(u, pred, curve)
  local p = units[u] and units[u].hp / units[u].max or 1
  if curve and curve.AddPoint and pts then local v = 0; for _, q in ipairs(pts) do if p >= q[1] then v = q[2] end end; return v end
  return p
end
L("guard curve built: " .. tostring(NS.GuardCurve(true) and true) .. " points " .. #pts)
NS.DrawGuard(TwizHealBar2, "party1")   -- hidden-health path
L("hidden 85% -> " .. TwizHealBar2.guard:GetValue())
units.party1.hp = 1800; NS.DrawGuard(TwizHealBar2, "party1")
L("hidden 90% -> " .. TwizHealBar2.guard:GetValue())
units.party1.hp = 1810; NS.DrawGuard(TwizHealBar2, "party1")
L("hidden 90.5% -> " .. TwizHealBar2.guard:GetValue())
UnitHealthPercent = realPct
]==]
assert(loadstring(src .. "\n" .. rest))()
