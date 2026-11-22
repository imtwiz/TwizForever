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
  nameplate1 = { name = "Passerby", class = "PALADIN", power = 0, auras = {} },
  nameplate2 = { name = "Flagged", class = "MAGE", power = 0, auras = {}, pvp = true },
  nameplate3 = { name = "Sue", class = "MAGE", power = 0, auras = {}, same = "party2" },
}
UnitIsUnit = function(a, b) return a == b end
UnitIsPVP = function(u) return units[u] and units[u].pvp or false end
SIM.cvars = { nameplateShowFriends = "0" }
GetCVar = function(k) return SIM.cvars[k] end
SetCVar = function(k, v) SIM.cvars[k] = tostring(v) end
UnitExists = function(u) return units[u] ~= nil end
UnitGUID = function(u) local x = units[u] if not x then return nil end return "GUID-" .. (x.same and units[x.same].name or x.name) end
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
L("friendly nameplates now: " .. SIM.cvars.nameplateShowFriends)
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
SlashCmdList.TWIZBUFF("strangers off"); SIM.Advance(1.5)
L("strangers off: " .. show() .. " | plates " .. SIM.cvars.nameplateShowFriends)
SlashCmdList.TWIZBUFF("wheel on"); SIM.Advance(1.5)
L("wheel: " .. tostring(SIM.overrides["MOUSEWHEELDOWN"]))
-- shared key with TwizHeal
TwizHealButton = CreateFrame("Button", "TwizHealButton")
TwizHeal = { pick = nil }
SIM.Advance(1.5)
L("with TwizHeal, nobody hurt: " .. tostring(TwizBuffButton:GetAttribute("macrotext")):gsub("\n", " || ") .. " | " .. TwizBuffButton.label:GetText())
-- 1.5.2: TwizHeal picks people at full health to pre-HoT them - that must not take the buff key
TwizHeal.pick = { unit = "party2", name = "Sue", pct = 1 }
SIM.Advance(1.5)
local prehot = TwizBuffButton.label:GetText()
L("pre-HoT pick at 100%: " .. tostring(TwizBuffButton:GetAttribute("macrotext")):gsub("\n", " || ") .. " | " .. prehot)
assert(not prehot:find("^Heal"), "buff key must still buff")
TwizHeal.pick = { unit = "party2", name = "Sue", pct = 0.6 }
SIM.Advance(1.5)
L("someone hurt: " .. tostring(TwizBuffButton:GetAttribute("macrotext")):gsub("\n", " || ") .. " | " .. TwizBuffButton.label:GetText())
assert(TwizBuffButton.label:GetText():find("^Heal"))
-- 1.6.0: Cat Form without Track Humanoids -> that's the key's first job
TwizHeal.pick = nil
SIM.known["Track Humanoids"] = 5225
UnitClass = function() return "druid", "DRUID" end
local form, tracking = 0, false
GetShapeshiftFormID = function() return form == 1 and 1 or nil end
C_Minimap = { GetNumTrackingTypes = function() return 1 end,
  GetTrackingInfo = function(i) return { name = "Track Humanoids", active = tracking } end }
SIM.Advance(1.5)
L("caster form: " .. TwizBuffButton.label:GetText())
assert(not TwizBuffButton.label:GetText():find("Track"))
form = 1; SIM.Fire("UPDATE_SHAPESHIFT_FORM"); SIM.Advance(1.5)
L("cat form, not tracking: " .. tostring(TwizBuffButton:GetAttribute("macrotext")):gsub("\n", " || ") .. " | " .. TwizBuffButton.label:GetText())
assert(TwizBuffButton:GetAttribute("macrotext"):find("/cast %[nocombat%] Track Humanoids"))
tracking = true; SIM.Fire("MINIMAP_UPDATE_TRACKING"); SIM.Advance(1.5)
L("cat form, tracking: " .. TwizBuffButton.label:GetText())
assert(not TwizBuffButton.label:GetText():find("Track"))
