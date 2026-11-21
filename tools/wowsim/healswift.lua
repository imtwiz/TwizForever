-- TwizHeal 1.12: Regrowth vs Rejuvenation by how much is missing; Swiftmend below 31%
local f = io.open(REPO .. "/tools/wowsim/healrules.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("SIM.Advance%(0.3%); L%(\"1 tank 90%%") - 1)
local rest = [==[
local NS = TwizHeal
local L = function(s) SIM.log[#SIM.log + 1] = s end
local known = { Swiftmend = true }
C_Spell.GetSpellInfo = function(n) if known[n] or n == "Healing Touch" or n == "Regrowth" or n == "Rejuvenation" then return { name = n } end end
C_Spell.GetSpellCooldown = function(n) return { startTime = 0, duration = 0 } end
local function rule(hp, hots, moving)
  units.party1.hp = hp; SIM.hots.party1 = hots; SIM.speed = moving and 7 or 0; NS.moving = moving
  local r, why = NS.OocRule("party1")
  return (r and r.label or "-") .. " (" .. tostring(why) .. ")"
end
L("tank 95%, nothing on:        " .. rule(1900, nil))
L("tank 85%, Rejuv on:          " .. rule(1700, { { "Rejuvenation", 10 } }))
L("tank 70%, Rejuv on:          " .. rule(1400, { { "Rejuvenation", 10 } }))
L("tank 50%, nothing on:        " .. rule(1000, nil))
L("tank 50%, Regrowth on:       " .. rule(1000, { { "Regrowth", 15 } }))
L("tank 25%, Rejuv on:          " .. rule(500, { { "Rejuvenation", 10 } }))
L("tank 25%, nothing on:        " .. rule(500, nil))
C_Spell.GetSpellCooldown = function(n) return { startTime = GetTime() - 2, duration = 15 } end
L("tank 25%, Swiftmend on cd:   " .. rule(500, { { "Rejuvenation", 10 } }))
L("tank 25%, moving, no Swift:  " .. rule(500, nil, true))
C_Spell.GetSpellCooldown = function(n) return { startTime = 0, duration = 0 } end
L("tank 25%, moving, Rejuv on:  " .. rule(500, { { "Rejuvenation", 10 } }, true))
SIM.Advance(0.3)
L("emergency key: " .. tostring(TwizHealButton:GetAttribute("macrotext3")):gsub("\n", " || "))
known.Swiftmend = nil
SIM.Advance(0.3)
L("no Swiftmend yet (level 25): " .. tostring(TwizHealButton:GetAttribute("macrotext3")):gsub("\n", " || ") .. " | 25%: " .. rule(500, nil))
L("binding: " .. tostring(_G["BINDING_NAME_CLICK TwizHealButton:MiddleButton"]))
-- 1.12.1: above 89% -> no heal
L("tank 95%:                    " .. rule(1900, nil))
L("tank 89%:                    " .. rule(1780, nil))
units.party1.hp = 1900; units.party2 = units.party2; SIM.hots.party1 = nil; NS.moving = false
TwizHeal.hoverUnit = "party1"; SIM.Advance(0.3)
L("hover tank at 95%, key: " .. tostring(TwizHealButton:GetAttribute("macrotext1")):gsub("\n", " || "))
TwizHeal.hoverUnit = nil
-- 1.13.0: downranked heals sized to the gap, cast by spell ID
units.party1.hp = 1700; SIM.hots.party1 = { { "Rejuvenation", 10 } }; NS.moving = false
local r, why = NS.OocRule("party1")
L(("tank 85%% with Rejuv (needs ~155 more): %s rank %s heals %d (%s), downranked=%s"):format(r.label, tostring(r.rank), r.total, why, tostring(NS.Downranked(r))))
TwizHeal.hoverUnit = "party1"; SIM.Advance(0.3)
L("key: " .. tostring(TwizHealButton:GetAttribute("macrotext1")):gsub("\n", " || ") .. " | cast button spell " .. tostring(TwizHealCastKey and TwizHealCastKey:GetAttribute("spell")) .. " on " .. tostring(TwizHealCastKey and TwizHealCastKey:GetAttribute("unit")))
L("bar2 heal: " .. tostring(TwizHealBar2:GetAttribute("healmacro")):gsub("\n", " || "))
units.party1.hp = 1200; SIM.hots.party1 = nil; NS.moving = true
local r2 = NS.OocRule("party1")
L(("moving, tank 60%%: %s rank %s"):format(r2.label, tostring(r2.rank)))
NS.moving = false; TwizHeal.hoverUnit = nil
-- 1.13.2: the lowest gets healed, not the tank first
units.party1.hp = 1600; SIM.hots.party1 = nil   -- tank 80%
units.party2.hp = 650                             -- rogue 50%
local p = NS.Pick(NS.Scan())
L("tank 80%, rogue 50% -> pick: " .. tostring(p and p.name))
units.party2.hp = 1050                            -- rogue ~81%
p = NS.Pick(NS.Scan())
L("tank 80%, rogue 81% (near-tie) -> pick: " .. tostring(p and p.name))
units.party2.hp = 1300; units.party1.hp = 2000
-- 1.14.0: lowest marker (health readable), color curve (health hidden)
units.party1.hp = 1600; units.party2.hp = 650; SIM.Advance(0.3)
L(("LOWEST marker: tank %s, rogue %s"):format(tostring(TwizHealBar2.lowMark and TwizHealBar2.lowMark.__shown), tostring(TwizHealBar3.lowMark and TwizHealBar3.lowMark.__shown)))
-- hidden health: the game turns it into a color for us
local evaluated = 0
C_CurveUtil = { CreateColorCurve = function() return { SetType = function() end, AddPoint = function() end } end }
CreateColor = function(r, g, b) return { r = r, g = g, b = b } end
Enum = Enum or {}; Enum.LuaCurveType = { Linear = 1 }
UnitHealthPercent = function(u, pred, curve) evaluated = evaluated + 1; return { GetRGB = function() return 1, 0.2, 0.2 end } end
issecretvalue = function(v) return v == "SECRET" end
local realHealth = UnitHealth
UnitHealth = function(u) return "SECRET" end
SIM.Advance(0.3)
L(("health hidden: color from the game's curve for %d bars; rogue LOWEST marker now %s"):format(evaluated, tostring(TwizHealBar3.lowMark.__shown)))
UnitHealth = realHealth; issecretvalue = function() return false end
units.party2.hp = 1300; units.party1.hp = 2000
-- 1.14.1: which rank went out
C_Spell.GetSpellName = function(id) return ({ [5188] = "Healing Touch", [1430] = "Rejuvenation", [8938] = "Regrowth" })[id] end
SIM.Fire("UNIT_SPELLCAST_SENT", "player", "Tank", "guid", 5188)
L("cast line: " .. tostring(NS.castLine and NS.castLine:GetText()))
SIM.Fire("UNIT_SPELLCAST_SENT", "player", "Rogue", "guid", 1430)
L("cast line: " .. tostring(NS.castLine and NS.castLine:GetText()))
]==]
assert(loadstring(src .. "\n" .. rest))()
