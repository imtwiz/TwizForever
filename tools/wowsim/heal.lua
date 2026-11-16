-- TwizHeal: pick (danger first, then tank > healer > dps by lowest %), right-sized rank, button macro
local L = function(s) SIM.log[#SIM.log + 1] = s end
SIM.class = "PRIEST"
local units = {
  player = { name = "Kitty", class = "PRIEST", hp = 900, max = 1000 },
  party1 = { name = "Tank", class = "WARRIOR", hp = 1400, max = 2000 },
  party2 = { name = "Rogue", class = "ROGUE", hp = 520, max = 1300 },
  party3 = { name = "Mage", class = "MAGE", hp = 1000, max = 1000 },
}
UnitExists = function(u) return units[u] ~= nil end
UnitName = function(u) return units[u] and units[u].name end
UnitClass = function(u) local x = units[u or "player"] return x.class:lower(), x.class end
UnitHealth = function(u) return units[u].hp end
UnitHealthMax = function(u) return units[u].max end
UnitIsConnected = function() return true end
UnitIsDeadOrGhost = function() return false end
UnitIsUnit = function(a, b) return a == b end
UnitInRange = function() return true, true end
UnitGroupRolesAssigned = function() return "NONE" end
UnitThreatSituation = function() return 0 end
UnitPower = function() return SIM.mana or 2000 end
SIM.hots = {}
GetTime = GetTime
C_UnitAuras = { GetAuraDataByIndex = function(u, i) local h = SIM.hots[u] and SIM.hots[u][i] if h then return { name = h[1], sourceUnit = "player", expirationTime = GetTime() + h[2] } end end }
IsInRaid = function() return false end
-- spellbook: Lesser Heal 1-3, Heal 1-2, Flash Heal 1
local book = {
  { "Lesser Heal", "Rank 1", 2050, "Heal your target for 46 to 56." , 30 },
  { "Lesser Heal", "Rank 3", 2053, "Heal your target for 135 to 158.", 75 },
  { "Heal", "Rank 1", 2054, "Heal your target for 295 to 341.", 155 },
  { "Heal", "Rank 2", 2055, "Heal your target for 429 to 491.", 205 },
  { "Flash Heal", "Rank 1", 2061, "Heals a friendly target for 193 to 237.", 125 },
  { "Renew", "Rank 1", 139, "Heals the target of 45 damage over 15 sec.", 30 },
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
-- a spell whose text never loads, and a load request that fires its event right away
book[#book + 1] = { "Greater Heal", "Rank 1", 2060, "", 300 }
desc[2060], cost[2060] = "", 300
SIM.loadReq = 0
C_Spell.RequestLoadSpellData = function(id) SIM.loadReq = SIM.loadReq + 1; SIM.Fire("SPELL_DATA_LOAD_RESULT", id, true); SIM.Fire("SPELLS_CHANGED") end
local NS = SIM.LoadAddon(REPO .. "/TwizHeal", "TwizHeal")
SIM.Fire("ADDON_LOADED", "TwizHeal"); SIM.Fire("PLAYER_ENTERING_WORLD"); SIM.Advance(0.5)
SIM.Advance(30)
L("load requests after 30s: " .. SIM.loadReq)
local o = {} for _, r in ipairs(NS.ranks) do o[#o + 1] = r.label .. "=" .. r.avg .. (r.fast and "F" or "") end
L("ranks: " .. table.concat(o, ", "))
local function now()
  local p, em = NS.Pick()
  return (p and (p.name .. " " .. math.floor(p.pct * 100) .. "% " .. p.role) or "nobody") .. (em and " DANGER" or "")
    .. " | " .. tostring(TwizHealFrame.next:GetText()):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end
SIM.Advance(0.3); L("1: " .. now())
L("macro: " .. tostring(TwizHealButton:GetAttribute("macrotext")))
units.party2.hp = 300; SIM.Advance(0.3); L("2 (rogue in danger): " .. now())
units.party2.hp = 1300; units.party1.hp = 1950; SIM.Advance(0.3); L("3 (tank nearly full, healer 90%): " .. now())
units.player.hp = 1000; units.party1.hp = 2000; SIM.Advance(0.3); L("4 (all full): " .. now())
units.party1.hp = 1500; SIM.mana = 100; SIM.Advance(0.3); L("5 (tank -500, low mana): " .. now())
L("bar 2 macro: " .. tostring(TwizHealBar2:GetAttribute("macrotext")))
SIM.mana = 2000
-- tank at 90% with your Renew ticking (covers the gap): no heal needed; without it: Renew
units.party1.hp = 1960; SIM.hots.party1 = { { "Renew", 14 } }; SIM.Advance(0.3); L("6 (tank -40, Renew up): " .. now())
SIM.hots.party1 = nil; SIM.Advance(0.3); L("7 (tank -40, no Renew): " .. now())
-- rogue at 60%: big need -> direct heal sized to what Renew won't cover
units.party2.hp = 780; SIM.Advance(0.3); L("8 (rogue 60%): " .. now())
-- the game hides health (secret values): no errors, that person is skipped, bars still drawn
issecretvalue = function(v) return v == "SECRET" end
units.party2.hp = "SECRET"; units.party1.hp = 1200
SIM.Advance(0.3); L("9 (rogue hidden): " .. now() .. " | shown=" .. tostring(TwizHealFrame.__shown))
for _, u in pairs(units) do u.hp = "SECRET" end
SIM.Advance(0.3); L("10 (all hidden): " .. now())
SlashCmdList.TWIZHEAL("debug")
L("hidden-mode key: " .. tostring(TwizHealButton:GetAttribute("macrotext")))
L("hidden-mode bar: " .. tostring(TwizHealBar2:GetAttribute("macrotext")))
-- the game's party/raid frames get Alt-click heals
local pf = CreateFrame("Button", "CompactPartyFrameMember2")
local rf = CreateFrame("Button", "CompactRaidFrame7")
TwizHeal.ApplyClickCast()
L("party frame alt-click: " .. tostring(pf:GetAttribute("alt-type1")) .. " / " .. tostring(pf:GetAttribute("alt-macrotext1")))
L("raid frame alt-right (gone): " .. tostring(rf:GetAttribute("alt-macrotext2")) .. " | ctrl-alt: " .. tostring(rf:GetAttribute("alt-ctrl-macrotext1")))
local late = CreateFrame("Button", "LateFrame")
ClickCastFrames[late] = true
L("frame registered later: " .. tostring(late:GetAttribute("alt-macrotext1")))
L("own window shown: " .. tostring(TwizHealFrame.__shown))
