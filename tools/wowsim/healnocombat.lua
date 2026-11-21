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
assert(not key:find("%[combat") and not key:find("%[@") and not key:find("^/cast %[@"), "key must not heal in combat")
local bar = tostring(TwizHealBar1:GetAttribute("healmacro"))
L("bar1 heal: " .. bar:gsub("\n", " || "))
assert(bar:find("%[combat%]") or bar:find("combat,"), "bar keeps its combat heal")
local b = TwizHealBar1
assert(b.blockFill and b.blockTop, "blockers built")
L("blockers out of combat shown: " .. tostring(b.blockFill:IsShown()) .. "/" .. tostring(b.blockTop:IsShown()))
SIM.Fire("PLAYER_REGEN_DISABLED")
L("blockers in combat shown: " .. tostring(b.blockFill:IsShown()) .. "/" .. tostring(b.blockTop:IsShown()))
-- 1.23.1: no health curve in this client -> nothing blocks the bars (fail open)
assert(not b.blockFill:IsShown() and not b.blockTop:IsShown(), "no curve: bars must stay clickable")
-- with the curve: whole-bar blocker only
b.useGuard = true; NS.SetBlockers(true)
L("with curve, in combat: blockFill " .. tostring(b.blockFill:IsShown()) .. ", blockTop " .. tostring(b.blockTop:IsShown()))
assert(b.blockFill:IsShown() and not b.blockTop:IsShown())
db = TwizHealDB; TwizHealDB.combatGuard = false; NS.SetBlockers(true)
assert(not b.blockFill:IsShown(), "/th guard off")
TwizHealDB.combatGuard = nil; b.useGuard = nil; NS.SetBlockers(true)
-- after-fight report: presses but no spell went out
NS.FightStart()
for i = 1, 4 do TwizHealBar2:GetScript("PreClick")(TwizHealBar2) end
NS.FightCount("err", "Spell is not ready yet."); NS.FightCount("err", "Spell is not ready yet.")
NS.FightEnd()
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
-- 1.18.0: out of combat pre-HoT - one Regrowth and one Rejuvenation each, tank first
units.party1.hp = 2000; units.party2.hp = 1300; units.player.hp = 1000
SIM.hots.party1 = nil; SIM.hots.party2 = nil; SIM.hots.player = nil
local function who() local p = NS.Pick(NS.Scan()); local r, why = p and NS.OocRule(p.unit); return (p and p.name or "-") .. ": " .. (r and r.label or "-") .. " (" .. tostring(why) .. ")" end
L("all full, nothing on: " .. who())
SIM.hots.party1 = { { "Regrowth", 21 } }
L("tank has Regrowth:    " .. who())
SIM.hots.party1 = { { "Regrowth", 21 }, { "Rejuvenation", 12 } }
L("tank has both:        " .. who())
SIM.hots.party2 = { { "Regrowth", 21 }, { "Rejuvenation", 12 } }; SIM.hots.player = SIM.hots.party2
L("everyone has both:    " .. who())
-- 1.19.0: under 40% -> Nature's Swiftness + Healing Touch (when known and ready)
local realInfo = C_Spell.GetSpellInfo
C_Spell.GetSpellInfo = function(n) if n == "Nature's Swiftness" then return { name = n } end return realInfo(n) end
SIM.hots.party1 = nil; units.party1.hp = 700   -- tank 35%
local r, why = NS.OocRule("party1")
L(("tank 35%%: %s rank %s + %s (%s)"):format(r.label, tostring(r.rank), tostring(r.swift), why))
assert(r.swift == "Nature's Swiftness")
TwizHeal.hoverUnit = "party1"; SIM.Advance(0.3)
local k1 = tostring(TwizHealButton:GetAttribute("macrotext1"))
L("key on tank 35%: " .. k1:gsub("\n", " || "))
assert(k1:find("/cast %[nocombat%] Nature's Swiftness"))
L("NS key (button 4): " .. tostring(TwizHealButton:GetAttribute("macrotext4")):gsub("\n", " || "))
L("bar2 NS strip: " .. tostring(TwizHealBar2.low:GetValue()))
assert(TwizHealBar2.low:GetValue() == 1)
units.party1.hp = 900  -- 45%
r, why = NS.OocRule("party1")
L(("tank 45%%: %s (%s), swift=%s"):format(r.label, why, tostring(r.swift)))
C_Spell.GetSpellCooldown = function() return { startTime = GetTime() - 2, duration = 180 } end
units.party1.hp = 700
r, why = NS.OocRule("party1")
L(("tank 35%%, NS on cooldown: %s (%s)"):format(r.label, why))
C_Spell.GetSpellCooldown = function() return { startTime = 0, duration = 0 } end
C_Spell.GetSpellInfo = realInfo; TwizHeal.hoverUnit = nil
r = NS.OocRule("party1")
L(("tank 35%%, no NS learned: %s"):format(r.label))
L("NS key without NS: " .. tostring(NS.QuickMacro("party1")):gsub("\n", " || "))
L("binding: " .. tostring(_G["BINDING_NAME_CLICK TwizHealButton:Button4"]))
-- 1.20.0: 3+ under 40% -> Tranquility; no key cuts the channel
local info2 = C_Spell.GetSpellInfo
C_Spell.GetSpellInfo = function(n) if n == "Tranquility" then return { name = n } end return info2(n) end
units.player.hp = 300; units.party1.hp = 700; units.party2.hp = 400   -- 30%, 35%, 31%
NS.lowAt = nil
local r3, w3 = NS.OocRule("party1")
L(("3 under 40%%: %s (%s)"):format(r3.label, w3))
assert(r3.label == "Tranquility")
SIM.Advance(0.3)
local k = tostring(TwizHealButton:GetAttribute("macrotext1"))
L("key: " .. k:gsub("\n", " || "))
assert(k:find("^/stopmacro %[channeling:Tranquility%]") and k:find("/cast %[nocombat%] Tranquility"))
L("Tranquility key (button 5): " .. tostring(TwizHealButton:GetAttribute("macrotext5")):gsub("\n", " || "))
L("emergency key: " .. tostring(TwizHealButton:GetAttribute("macrotext3")):gsub("\n", " || "))
L("bar1 heal: " .. tostring(TwizHealBar1:GetAttribute("healmacro")):gsub("\n", " || "))
units.party2.hp = 1300; NS.lowAt = nil
local r2 = NS.OocRule("party1")
L(("only 2 under 40%%: %s"):format(r2.label))
assert(r2.label ~= "Tranquility")
NS.moving = true; units.party2.hp = 400; NS.lowAt = nil
L(("3 under 40%%, moving: %s"):format(NS.OocRule("party1").label))
NS.moving = false
C_Spell.GetSpellInfo = info2
units.player.hp = 1000; units.party1.hp = 2000; units.party2.hp = 1300
-- 1.20.1: pre-HoT with someone else's hidden buff on them, and with health hidden
issecretvalue = function(v) return v == "SECRET" end
local realIdx = C_UnitAuras.GetAuraDataByIndex
C_UnitAuras.GetAuraDataByIndex = function(u, i, filter)
  local list = { { name = "SECRET", sourceUnit = "SECRET" } }   -- a priest's buff the game hides
  for _, h in ipairs(SIM.hots[u] or {}) do list[#list + 1] = { name = h[1], sourceUnit = "player", expirationTime = GetTime() + h[2] } end
  if filter and filter:find("PLAYER") then table.remove(list, 1) end
  return list[i]
end
SIM.hots.party1 = nil; SIM.hots.party2 = nil; SIM.hots.player = nil
L("hidden priest buff, all full: " .. who())
assert(who():find("Tank: Regrowth"))
SIM.hots.party1 = { { "Regrowth", 21 } }
L("tank has Regrowth:            " .. who())
local realH = UnitHealth
UnitHealth = function(u) return "SECRET" end
SIM.hots.party1 = nil
local r = NS.OocRule("party1")
L("health hidden, nothing on: " .. tostring(r and r.label))
assert(r and r.label == "Regrowth")
SIM.hots.party1 = { { "Regrowth", 21 }, { "Rejuvenation", 12 } }
L("health hidden, both on:    " .. tostring(NS.OocRule("party1") and NS.OocRule("party1").label))
SIM.hots.party1 = nil
local p = NS.Pick(NS.Scan())
L("health hidden, pick: " .. tostring(p and p.name))
SIM.Fire("PLAYER_ENTERING_WORLD")
SlashCmdList["TWIZHEAL"]("prehot")
UnitHealth = realH; C_UnitAuras.GetAuraDataByIndex = realIdx
-- 1.23.0: no 89% limit out of combat - full health with both HoTs on still gets a small heal
units.party1.hp = 2000; SIM.hots.party1 = { { "Regrowth", 21 }, { "Rejuvenation", 12 } }
local rr, ww = NS.OocRule("party1")
L(("tank 100%%, both HoTs on: %s rank %s (%s)"):format(rr and rr.label or "-", tostring(rr and rr.rank), tostring(ww)))
assert(rr and rr.label == "Healing Touch" and rr.rank == 1)
-- 1.21.0: mana under 50% -> Read Leyline when ready (Skyborne racial)
local info3 = C_Spell.GetSpellInfo
C_Spell.GetSpellInfo = function(n) if n == "Read Leyline" then return { name = n } end return info3(n) end
local mana = 1000
UnitPower = function(u, t) return u == "player" and mana or 0 end
UnitPowerMax = function(u, t) return 2000 end
units.player.hp = 1000; units.party1.hp = 2000; units.party2.hp = 1300
SIM.hots.party1 = { { "Regrowth", 21 }, { "Rejuvenation", 12 } }; NS.lowAt = nil
mana = 900   -- 45%
local r, why = NS.OocRule("party1")
L(("mana 45%%: %s (%s)"):format(r and r.label or "-", tostring(why)))
assert(r and r.label == "Read Leyline")
TwizHeal.hoverUnit = nil; SIM.Advance(0.3)
L("key: " .. tostring(TwizHealButton:GetAttribute("macrotext1")):gsub("\n", " || "))
mana = 1600  -- 80%
r = NS.OocRule("party1")
L(("mana 80%%: %s"):format(r and r.label or "nothing"))
mana = 1500  -- exactly 75%
r = NS.OocRule("party1")
L(("mana 75%%: %s"):format(r and r.label or "nothing"))
assert(r and r.label == "Read Leyline")
mana = 900; C_Spell.GetSpellCooldown = function() return { startTime = GetTime() - 5, duration = 120 } end
r = NS.OocRule("party1")
L(("mana 45%%, on cooldown: %s"):format(r and r.label or "nothing"))
C_Spell.GetSpellCooldown = function() return { startTime = 0, duration = 0 } end
units.party1.hp = 700; SIM.hots.party1 = nil
r = NS.OocRule("party1")
L(("mana 45%%, tank at 35%%: %s"):format(r and r.label or "nothing"))
assert(r.label ~= "Read Leyline")
units.party1.hp = 1700; SIM.hots.party1 = nil; mana = 1800
TwizHeal.hoverUnit = "party1"; SIM.Advance(0.3)
local hm = tostring(TwizHealBar2:GetAttribute("healmacro"))
L("bar2 heal with Read Leyline known: " .. hm:gsub("\n", " || "))
assert(hm:find("/cast %[combat%] Read Leyline\n/click %[combat%]") or hm:find("/cast %[combat%] Read Leyline\n/castsequence"))
local base = tostring(TwizHealButton:GetAttribute("basemacro"))
assert(not base:find("%[combat%] Read Leyline"), "no-hover key stays silent in combat")
-- the "not ready" error from Read Leyline is hidden right after a TwizHeal press, others shown
local shown = {}
UIErrorsFrame = CreateFrame("Frame", "UIErrorsFrame")
UIErrorsFrame:SetScript("OnEvent", function(_, e, t, msg) shown[#shown + 1] = msg end)
SPELL_FAILED_NOT_READY = "Spell is not ready yet."
NS.errHooked = nil; NS.HideNotReady()
local h = UIErrorsFrame:GetScript("OnEvent")
NS.clickAt = GetTime(); h(UIErrorsFrame, "UI_ERROR_MESSAGE", 1, "Spell is not ready yet.")
h(UIErrorsFrame, "UI_ERROR_MESSAGE", 1, "Out of range.")
SIM.Advance(2); h(UIErrorsFrame, "UI_ERROR_MESSAGE", 1, "Spell is not ready yet.")
L("errors shown: " .. table.concat(shown, " | "))
assert(#shown == 2 and shown[1] == "Out of range.")
TwizHeal.hoverUnit = nil
units.party1.hp = 2000; C_Spell.GetSpellInfo = info3
]==]
assert(loadstring(src .. "\n" .. rest))()
