-- TwizBuff: who is missing your class buffs, and what the cast button is set to
local L = function(s) SIM.log[#SIM.log + 1] = s end
-- a druid in a party of 3 + a friendly target outside the group
SIM.class = "DRUID"
local units = {
  player = { name = "Kitty", class = "DRUID", power = 0, auras = {} },
  party1 = { name = "Bob", class = "WARRIOR", power = 1, auras = { "Mark of the Wild" } },
  party2 = { name = "Sue", class = "MAGE", power = 0, auras = {} },
  party3 = { name = "Far", class = "PRIEST", power = 0, auras = {}, far = true },
  target = { name = "Stranger", class = "ROGUE", power = 3, auras = {} },
}
UnitExists = function(u) return units[u] ~= nil end
UnitGUID = function(u) return units[u] and ("GUID-" .. units[u].name) end
UnitName = function(u) return units[u] and units[u].name end
UnitClass = function(u) local x = units[u or "player"] return x.class:lower(), x.class end
UnitPowerType = function(u) return units[u].power end
UnitIsConnected = function() return true end
UnitIsDeadOrGhost = function() return false end
UnitIsPlayer = function(u) return units[u] ~= nil end
UnitIsFriend = function() return true end
UnitIsVisible = function() return true end
IsInRaid = function() return false end
C_UnitAuras = { GetAuraDataByIndex = function(u, i) local n = units[u] and units[u].auras[i] return n and { name = n } end }
SIM.known = { ["Mark of the Wild"] = 1126, ["Thorns"] = 467 }
C_Spell = C_Spell or {}
C_Spell.GetSpellInfo = function(name) local id = SIM.known[name] return id and { spellID = id, name = name } end
IsPlayerSpell = function(id) for _, v in pairs(SIM.known) do if v == id then return true end end return false end
C_Spell.IsSpellUsable = function(name) return SIM.known[name] ~= nil and (name ~= "Gift of the Wild" or SIM.haveBerries) end
C_Spell.IsSpellInRange = function(name, u) return not units[u].far end
RAID_CLASS_COLORS = {}
local NS = SIM.LoadAddon(REPO .. "/TwizBuff", "TwizBuff")
SIM.Fire("ADDON_LOADED", "TwizBuff"); SIM.Fire("PLAYER_ENTERING_WORLD"); SIM.Advance(1.5)
local function show()
  local o = {}
  for _, m in ipairs(NS.Missing()) do o[#o + 1] = m.spell .. ">" .. (m.name or m.unit) .. (m.inRange and "" or "(far)") end
  local b = TwizBuffButton
  return table.concat(o, ", ") .. "  || button: " .. tostring(b.label:GetText()) .. " [" .. tostring(b:GetAttribute("spell")) .. " @ " .. tostring(b:GetAttribute("unit")) .. "]"
end
L("druid: " .. show())
L("window: " .. tostring(TwizBuffFrame.__shown) .. ", " .. TwizBuffFrame.count:GetText())
-- 3 in the group need it and she knows Gift of the Wild with berries: group cast
units.party4 = { name = "Dee", class = "HUNTER", power = 0, auras = {} }
SIM.known["Gift of the Wild"] = 21849; SIM.haveBerries = true
SIM.Advance(1.5)
L("with Gift + berries: " .. show())
SIM.haveBerries = false; SIM.Advance(1.5)
L("no berries: " .. show())
-- everyone buffed -> window hides
for _, u in pairs(units) do u.auras = { "Mark of the Wild" } end
SIM.Advance(1.5)
L("all buffed: window shown=" .. tostring(TwizBuffFrame.__shown) .. " button=" .. TwizBuffButton.label:GetText())
-- a mage: Arcane Intellect only for mana users
SIM.class = "MAGE"; units.player.class = "MAGE"
SIM.known = { ["Arcane Intellect"] = 1459 }
for _, u in pairs(units) do u.auras = {} end
SIM.Advance(1.5)
L("mage: " .. show())
SlashCmdList.TWIZBUFF("wheel on"); SIM.Advance(1.5)
L("wheel: " .. tostring(SIM.overrides["MOUSEWHEELDOWN"]))
