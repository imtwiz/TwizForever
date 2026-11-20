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
SIM.known["Remove Curse"] = 2782; SIM.known["Cure Poison"] = 8946
SIM.debuffs = { party1 = { { "Curse of Weakness", "Curse" } }, party2 = { { "Spider Venom", "Poison" }, { "Hamstring" } } }
C_UnitAuras = { GetAuraDataByIndex = function(u, i, f)
  if f == "HARMFUL" then local d = SIM.debuffs[u] and SIM.debuffs[u][i] return d and { name = d[1], dispelName = d[2] } end
  local n = units[u] and units[u].auras[i] return n and { name = n } end }
local NS = SIM.LoadAddon(REPO .. "/TwizBuff", "TwizBuff")
SIM.Fire("ADDON_LOADED", "TwizBuff"); SIM.Fire("PLAYER_ENTERING_WORLD"); SIM.Advance(1.5)
local L = function(s) SIM.log[#SIM.log + 1] = s end
local function key() return (tostring(TwizBuffButton:GetAttribute("macrotext")):gsub("\n", " || ")) end
local d = {} for _, x in ipairs(NS.Debuffed()) do d[#d + 1] = x.spell .. "->" .. x.unit .. "(" .. x.debuff .. ")" end
L("debuffs: " .. table.concat(d, ", "))
L("key: " .. key() .. " | label: " .. tostring(TwizBuffButton.label:GetText()))
SIM.debuffs.party1 = nil; SIM.Fire("UNIT_AURA", "party1"); SIM.Advance(1)
L("after curse removed: " .. key())
SIM.debuffs.party2 = { { "Hamstring" } }; SIM.Fire("UNIT_AURA", "party2"); SIM.Advance(1)
L("only undispellable left: " .. key())
SlashCmdList.TWIZBUFF("cleanse"); SIM.debuffs.party1 = { { "Curse of Weakness", "Curse" } }; SIM.Advance(1)
L("cleanse off: " .. key())
-- 1.4.1: the game refuses aura reads (an error, in combat) - no Lua errors, nothing wrongly cast
C_UnitAuras.GetAuraDataByIndex = function() error("GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'TwizBuff'") end
local ok, err = pcall(NS.Update)
L("aura reads refused: update ok=" .. tostring(ok) .. " " .. tostring(err or ""))
-- 1.5.0: nearest friend missing Mark of the Wild (right button), and the nearest-friend toggle
C_UnitAuras.GetAuraDataByIndex = function(u, i, f)
  if f == "HARMFUL" then return nil end
  local n = units[u] and units[u].auras[i] return n and { name = n } end
SlashCmdList.TWIZBUFF("cleanse")
local yards = { party2 = 25, target = 8, nameplate1 = 40, player = 0 }
CheckInteractDistance = function(u, i) local d = yards[u] or 50 return (i == 3 and d <= 10) or (i == 4 and d <= 28) end
UnitPosition = nil
units.player.auras = { "Mark of the Wild" }
SIM.Advance(1)
L("nearest missing MotW: " .. tostring(TwizBuff.near and (TwizBuff.near.unit .. " " .. tostring(TwizBuff.near.yards))) .. " | right button: " .. tostring(TwizBuffButton:GetAttribute("macrotext2")))
L("main key, toggle off: " .. tostring(TwizBuffButton:GetAttribute("macrotext")):gsub("\n", " || "))
TwizBuff_ToggleNearest(); SIM.Advance(1)
L("main key, toggle ON:  " .. tostring(TwizBuffButton:GetAttribute("macrotext")):gsub("\n", " || ") .. " | label: " .. tostring(TwizBuffButton.label:GetText()))
units.target.auras = { "Mark of the Wild" }; SIM.Fire("UNIT_AURA", "target"); SIM.Advance(1)
L("target buffed -> next nearest: " .. tostring(TwizBuffButton:GetAttribute("macrotext")):gsub("\n", " || "))
SlashCmdList.TWIZBUFF("nearest"); SIM.Advance(1)
L("toggled off again: nearest=" .. tostring(TwizBuff.db.nearest))
L("bindings: " .. tostring(_G["BINDING_NAME_CLICK TwizBuffButton:RightButton"]) .. " / " .. tostring(_G["BINDING_NAME_TWIZBUFF_NEAREST"]))
-- 1.5.1: a low-level friend gets a lower rank of Mark of the Wild
local known = { [1126] = true, [5232] = true, [6756] = true }   -- ranks 1-3 (level 1, 10, 20)
IsPlayerSpell = function(id) return known[id] == true end
GetSpellLevelLearned = nil
TwizBuff.ClearRanks()
UnitLevel = function(u) return ({ player = 24, party2 = 23, target = 8, nameplate1 = 3 })[u] or 24 end
units.target.auras = {}
SlashCmdList.TWIZBUFF("nearest"); SIM.Advance(1)
L("level 8 nearest: " .. tostring(TwizBuffButton:GetAttribute("macrotext")):gsub("\n", " || ") .. " | cast button: spell " .. tostring(TwizBuffCast1 and TwizBuffCast1:GetAttribute("spell")) .. " on " .. tostring(TwizBuffCast1 and TwizBuffCast1:GetAttribute("unit")) .. " | label: " .. tostring(TwizBuffButton.label:GetText()))
units.target.auras = { "Mark of the Wild" }; SIM.Advance(1)
L("level 23 next: " .. tostring(TwizBuffButton:GetAttribute("macrotext")):gsub("\n", " || "))
