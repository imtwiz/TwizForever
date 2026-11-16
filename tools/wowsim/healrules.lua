-- TwizHeal 1.4: rules instead of Shift/Ctrl (druid)
local L = function(s) SIM.log[#SIM.log + 1] = s end
SIM.class = "DRUID"
local units = {
  player = { name = "Kitty", class = "DRUID", hp = 1000, max = 1000 },
  party1 = { name = "Tank", class = "WARRIOR", hp = 1800, max = 2000 },
  party2 = { name = "Rogue", class = "ROGUE", hp = 1300, max = 1300 },
}
UnitExists = function(u) return units[u] ~= nil end
UnitName = function(u) return units[u] and units[u].name end
UnitClass = function(u) local x = units[u or "player"] return x.class:lower(), x.class end
UnitHealth = function(u) return units[u].hp end
UnitHealthMax = function(u) return units[u].max end
UnitIsConnected = function() return true end
UnitIsDeadOrGhost = function() return false end
UnitIsUnit = function(a, b) return a == b end
UnitCanAssist = function() return true end
UnitInRange = function() return true, true end
UnitGroupRolesAssigned = function() return "NONE" end
UnitThreatSituation = function() return 0 end
UnitPower = function() return 3000 end
SIM.speed = 0
GetUnitSpeed = function() return SIM.speed end
SIM.hots = {}
C_UnitAuras = { GetAuraDataByIndex = function(u, i) local h = SIM.hots[u] and SIM.hots[u][i] if h then return { name = h[1], sourceUnit = "player", expirationTime = GetTime() + h[2] } end end }
IsInRaid = function() return false end
local book = {
  { "Healing Touch", "Rank 1", 5185, "Heals a friendly target for 40 to 55.", 25 },
  { "Healing Touch", "Rank 3", 5188, "Heals a friendly target for 199 to 244.", 110 },
  { "Healing Touch", "Rank 4", 5189, "Heals a friendly target for 406 to 497.", 185 },
  { "Regrowth", "Rank 2", 8938, "Heals a friendly target for 176 to 197 and another 182 over 21 sec.", 164 },
  { "Rejuvenation", "Rank 4", 1430, "Heals the target for 175 damage over 12 sec.", 90 },
}
C_SpellBook = nil
GetNumSpellTabs = function() return 1 end
GetSpellTabInfo = function() return "General", 0, 0, #book end
GetSpellBookItemName = function(i) return book[i][1], book[i][2] end
GetSpellBookItemInfo = function(i) return "SPELL", book[i][3] end
C_Spell = C_Spell or {}
local desc, cost = {}, {}
for _, b in ipairs(book) do desc[b[3]] = b[4]; cost[b[3]] = b[5] end
C_Spell.GetSpellDescription = function(id) return desc[id] end
C_Spell.GetSpellPowerCost = function(id) return { { cost = cost[id] } } end
local NS = SIM.LoadAddon(REPO .. "/TwizHeal", "TwizHeal")
SIM.Fire("ADDON_LOADED", "TwizHeal"); SIM.Fire("PLAYER_ENTERING_WORLD"); SIM.Advance(0.5)
local function txt() return (tostring(TwizHealFrame.next:GetText()):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function key() return (tostring(TwizHealButton:GetAttribute("macrotext")):gsub("\n", " || ")) end
SIM.Advance(0.3); L("1 tank 90%, no HoT: " .. txt())
L("   key: " .. key())
SIM.hots.party1 = { { "Rejuvenation", 10 } }; SIM.Advance(0.3); L("2 tank 90%, Rejuv on: " .. txt())
SIM.speed = 7; SIM.Fire("PLAYER_STARTED_MOVING"); L("3 moving: " .. txt())
SIM.speed = 0; SIM.Fire("PLAYER_STOPPED_MOVING")
units.party1.hp = 800; SIM.Advance(0.3); L("4 tank 40%, Rejuv on: " .. txt())
SIM.hots.party1 = { { "Regrowth", 15 } }; SIM.Advance(0.3); L("5 tank 40%, Regrowth on: " .. txt())
units.party1.hp = 2000; SIM.hots.party1 = nil; SIM.Advance(0.3); L("6 everyone full: " .. txt())
units.target = { name = "Stranger", class = "MAGE", hp = 900, max = 1000 }
SIM.Fire("PLAYER_TARGET_CHANGED"); L("7 friendly target 90%: " .. txt())
L("   key: " .. key())
-- secret auras: don't keep re-casting a HoT you can't see
issecretvalue = function(v) return v == "SECRET" end
SIM.hots.target = { { "SECRET", 5 } }
C_UnitAuras.GetAuraDataByIndex = function(u, i) local h = SIM.hots[u] and SIM.hots[u][i] if h then return { name = h[1] == "SECRET" and "SECRET" or h[1], sourceUnit = "player", expirationTime = GetTime() + h[2] } end end
SIM.Advance(0.3); L("8 target auras hidden: " .. txt())
InCombatLockdown = function() return true end; SIM.Fire("PLAYER_REGEN_DISABLED"); SIM.Advance(0.3); L("9 in combat: " .. txt())
local pf = CreateFrame("Button", "CompactPartyFrameMember2")
InCombatLockdown = function() return false end; TwizHeal.ApplyClickCast()
L("alt-click: " .. tostring(pf:GetAttribute("alt-macrotext1")) .. " | alt-right: " .. tostring(pf:GetAttribute("alt-type2")))
local all = key() .. tostring(pf:GetAttribute("alt-macrotext1"))
L("any modifier in key: " .. tostring(all:find("mod:") ~= nil))
-- feedback after a press (1.4.1)
SIM.log2 = {}
local oldprint = print; print = function(m) L("CHAT " .. tostring(m)) end
units.target = nil; SIM.hots = {}
local function press() local f = TwizHealButton.__scripts.PostClick if f then f(TwizHealButton, "LeftButton", true) end end
press(); SIM.Advance(0.3); SIM.Fire("UI_ERROR_MESSAGE", 51, "Out of range."); SIM.Advance(0.5)
press(); SIM.Advance(0.1); SIM.Fire("UNIT_SPELLCAST_START", "player"); SIM.Fire("UI_ERROR_MESSAGE", 52, "Another action is in progress"); SIM.Advance(0.7)
SIM.Advance(1); press(); SIM.Advance(0.8)
SlashCmdList.TWIZHEAL("test")
-- a client that doesn't accept "Spell(Rank N)": labels become plain names
C_Spell.GetSpellInfo = function(n) if n:find("%(") then return nil end return { name = n } end
pcall(NS.ReadRanks); InCombatLockdown = function() return false end; SIM.Advance(0.3)
L("no-rank client key: " .. key())
print = oldprint
-- 1.5.0: party window back, hover a bar + key heals that bar's person (secure enter/leave swap)
L("window shown by default: " .. tostring(TwizHeal.db.shown))
local b2 = TwizHealBar2
L("bar2 heal macro: " .. tostring(b2:GetAttribute("healmacro")):gsub("\n", " || "))
L("bar2 clicks: " .. tostring(b2:GetAttribute("type")) .. " | onenter set: " .. tostring(b2:GetAttribute("_onenter") ~= nil))
TwizHeal.hoverUnit = "party1"; SIM.Advance(0.3)
L("hovering bar2, key: " .. key())
L("window: " .. txt())
TwizHeal.hoverUnit = nil; SIM.Advance(0.3)
L("left bar, key back to: " .. key())
-- 1.5.1: move + resize
TwizHeal.db.width, TwizHeal.db.barH = 300, 30; TwizHeal.Layout()
L(("resized: window %dx%d, bar1 %dx%d"):format(TwizHealFrame:GetWidth(), TwizHealFrame:GetHeight(), TwizHealBar1:GetWidth(), TwizHealBar1:GetHeight()))
