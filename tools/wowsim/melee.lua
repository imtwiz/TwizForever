-- TwizRogue and TwizWarrior: what the keys are set to
local L = function(s) SIM.log[#SIM.log + 1] = s end
C_Timer.NewTicker = C_Timer.NewTicker or function() return {} end
local known = {}
C_Spell = C_Spell or {}
C_Spell.GetSpellInfo = function(n) local id = known[n]; return id and { spellID = id, name = n } end
IsPlayerSpell = function(id) for _, v in pairs(known) do if v == id then return true end end return false end
local buffs = {}
C_UnitAuras = C_UnitAuras or {}
C_UnitAuras.GetAuraDataBySpellName = function(u, n) return buffs[n] and { name = n } or nil end
local weapons = { [16] = "item:7001", [17] = "item:7002" }
GetInventoryItemLink = function(u, slot) return weapons[slot] end
local bag = { [0] = {} }
C_Container = { GetContainerNumSlots = function(b) return b == 0 and 16 or 0 end,
  GetContainerItemInfo = function(b, s) local id = bag[b] and bag[b][s]; return id and { itemID = id } end }
local realGII = GetItemInfo
GetItemInfo = function(x)
  local id = tonumber(x) or tonumber(tostring(x):match("item:(%d+)"))
  if id == 7001 then return "Kris", nil, nil, 20, 15, "Weapon", "Daggers" end
  if id == 7002 then return "Shiv", nil, nil, 18, 15, "Weapon", "Daggers" end
  if id == 7003 then return "Buckler", nil, nil, 18, 15, "Armor", "Shields" end
  if id == 6947 then return "Instant Poison", nil, nil, 20 end
  if id == 6949 then return "Instant Poison II", nil, nil, 28 end
  if id == 2892 then return "Deadly Poison", nil, nil, 30 end
  return realGII and realGII(x)
end
local enchants = { false, false }
GetWeaponEnchantInfo = function() return enchants[1], 0, 0, 0, enchants[2] end

-- ROGUE
UnitClass = function() return "rogue", "ROGUE" end
for n, id in pairs({ ["Riposte"] = 14251, ["Stealth"] = 1784, ["Sinister Strike"] = 1752, ["Eviscerate"] = 2098, ["Ambush"] = 8676,
  ["Cheap Shot"] = 1833, ["Kick"] = 1766, ["Gouge"] = 1776, ["Slice and Dice"] = 5171 }) do known[n] = id end
bag[0] = { 6947, 6949, 2892 }
SIM.LoadAddon(REPO .. "/TwizRogue", "TwizRogue")
SIM.Fire("ADDON_LOADED", "TwizRogue"); SIM.Fire("PLAYER_ENTERING_WORLD"); SIM.Advance(0.5)
local function key(b, n) return tostring(_G[b]:GetAttribute("macrotext" .. n)):gsub("\n", " || ") end
L("rogue, no poison on: " .. key("TwizRogueButton", 1))
assert(key("TwizRogueButton", 1):find("/use %[nocombat%] Instant Poison II || /use %[nocombat%] 16", 1), "DBG " .. key("TwizRogueButton", 1))
enchants[1] = true; SIM.Fire("UNIT_INVENTORY_CHANGED", "player"); SIM.Advance(0.5)
L("main hand done: " .. key("TwizRogueButton", 1):sub(1, 70))
assert(key("TwizRogueButton", 1):find("Deadly Poison || /use %[nocombat%] 17"))
enchants[2] = true; SIM.Fire("UNIT_INVENTORY_CHANGED", "player"); SIM.Advance(0.5)
L("poisoned, dagger: " .. key("TwizRogueButton", 1))
assert(key("TwizRogueButton", 1):find("%[stealth,@target,harm,nodead%] Ambush"), "DBG " .. key("TwizRogueButton", 1))
assert(key("TwizRogueButton", 1):find("reset=target Sinister Strike, Sinister Strike, Sinister Strike, Eviscerate"))
L("interrupt: " .. key("TwizRogueButton", 2))
SlashCmdList.TWIZROGUE("snd")
L("with Slice and Dice: " .. key("TwizRogueButton", 1):match("castsequence.*"))

-- WARRIOR
UnitClass = function() return "warrior", "WARRIOR" end
known = { ["Revenge"] = 6572, ["Overpower"] = 7384, ["Battle Shout"] = 6673, ["Rend"] = 772, ["Heroic Strike"] = 78, ["Execute"] = 5308, ["Victory Rush"] = 34428,
  ["Charge"] = 100, ["Intercept"] = 20252, ["Pummel"] = 6552, ["Shield Bash"] = 72 }
weapons[17] = "item:7003"
SIM.LoadAddon(REPO .. "/TwizWarrior", "TwizWarrior")
SIM.Fire("ADDON_LOADED", "TwizWarrior"); SIM.Fire("PLAYER_ENTERING_WORLD"); SIM.Advance(0.5)
L("warrior, no shout: " .. key("TwizWarriorButton", 1))
assert(key("TwizWarriorButton", 1):find("reset=target Battle Shout, Rend, Heroic Strike, Heroic Strike, Heroic Strike, Heroic Strike, Heroic Strike, Heroic Strike || ") and not key("TwizWarriorButton", 1):find("null"), "DBG " .. key("TwizWarriorButton", 1))
buffs["Battle Shout"] = true; SIM.Fire("UNIT_AURA", "player"); SIM.Advance(0.5)
L("with shout: " .. key("TwizWarriorButton", 1))
assert(key("TwizWarriorButton", 1):find("reset=target Rend, Heroic Strike") and key("TwizWarriorButton", 1):find("Victory Rush"))
L("charge: " .. key("TwizWarriorButton", 2))
L("interrupt with a shield: " .. key("TwizWarriorButton", 3))
assert(key("TwizWarriorButton", 3):find("Shield Bash"))
assert(key("TwizWarriorButton", 1):find("/cast %[stance:1,@target,harm,nodead%] Overpower"))
L("overpower line present")
SlashCmdList.TWIZWARRIOR("overpower")
assert(not key("TwizWarriorButton", 1):find("Overpower"))
L("overpower off: gone")
-- reactives
assert(key("TwizRogueButton", 1):find("/startattack %[@target,harm,nodead%] || /cast %[@target,harm,nodead%] Riposte || /castsequence"), "DBG " .. key("TwizRogueButton", 1))
L("rogue Riposte before the builder sequence")
SlashCmdList.TWIZROGUE("reactives"); assert(not key("TwizRogueButton", 1):find("Riposte")); SlashCmdList.TWIZROGUE("reactives")
assert(key("TwizWarriorButton", 1):find("/cast %[stance:2,@target,harm,nodead%] Revenge"))
L("warrior: " .. key("TwizWarriorButton", 1))
SlashCmdList.TWIZWARRIOR("revenge"); assert(not key("TwizWarriorButton", 1):find("Revenge"))
L("revenge off: gone")
