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
]==]
assert(loadstring(src .. "\n" .. rest))()
