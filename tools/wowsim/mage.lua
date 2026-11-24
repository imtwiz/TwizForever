-- TwizMage: the keys, out-of-combat fixes, rune restock
local L = function(s) SIM.log[#SIM.log + 1] = s end
C_Timer.NewTicker = C_Timer.NewTicker or function() return {} end
UnitClass = function() return "mage", "MAGE" end
local known = { ["Frostbolt"] = 116, ["Fireball"] = 133, ["Fire Blast"] = 2136, ["Frost Armor"] = 168, ["Ice Armor"] = 7302,
  ["Conjure Water"] = 5504, ["Conjure Food"] = 587, ["Conjure Mana Agate"] = 759, ["Counterspell"] = 2139,
  ["Frost Nova"] = 122, ["Polymorph"] = 118, ["Blink"] = 1953, ["Evocation"] = 12051, ["Arcane Missiles"] = 5143,
  ["Teleport: Stormwind"] = 3561 }
C_Spell = C_Spell or {}
C_Spell.GetSpellInfo = function(n) local id = known[n]; return id and { spellID = id, name = n } end
IsPlayerSpell = function(id) for _, v in pairs(known) do if v == id then return true end end return false end
local buffs = {}
C_UnitAuras = C_UnitAuras or {}
C_UnitAuras.GetAuraDataBySpellName = function(u, n) return buffs[n] and { name = n } or nil end
local items = { [5350] = "Conjured Water", [2288] = "Conjured Fresh Water", [1113] = "Conjured Bread", [5514] = "Mana Agate",
  [17031] = "Rune of Teleportation", [17032] = "Rune of Portals" }
local bag = {}
C_Container = { GetContainerNumSlots = function(b) return b == 0 and 16 or 0 end,
  GetContainerItemInfo = function(b, s) local e = b == 0 and bag[s]; return e and { itemID = e[1], stackCount = e[2] } end }
local realGII = GetItemInfo
GetItemInfo = function(x)
  local id = tonumber(x) or tonumber(tostring(x):match("item:(%d+)"))
  if items[id] then return items[id], nil, nil, 1, 1, "Consumable", "", 20 end
  return realGII and realGII(x)
end

SIM.LoadAddon(REPO .. "/TwizMage", "TwizMage")
SIM.Fire("ADDON_LOADED", "TwizMage"); SIM.Fire("PLAYER_ENTERING_WORLD"); SIM.Advance(0.5)
local function key(n) return tostring(TwizMageButton:GetAttribute("macrotext" .. n)):gsub("\n", " || ") end
L("no armor: " .. key(1))
assert(key(1):find("^/cast %[combat,@target,harm,nodead%] Counterspell || /cast %[nocombat%] Ice Armor || /stopmacro %[nocombat%] || /cast %[@target,harm,nodead%] Fire Blast || /cast %[@target,harm,nodead%] Frostbolt$"), "DBG " .. key(1))
buffs["Ice Armor"] = true; SIM.Fire("UNIT_AURA", "player"); SIM.Advance(0.5)
L("armor up, no water: " .. key(1))
assert(key(1):find("/cast %[nocombat,noharm%] Conjure Water || /stopmacro %[nocombat,noharm%]"))
bag = { { 2288, 20 } }; SIM.Fire("BAG_UPDATE_DELAYED"); SIM.Advance(0.5)
L("water done: " .. key(1)); assert(key(1):find("Conjure Food"))
bag = { { 2288, 20 }, { 1113, 20 } }; SIM.Fire("BAG_UPDATE_DELAYED"); SIM.Advance(0.5)
L("food done: " .. key(1)); assert(key(1):find("Conjure Mana Agate"))
bag = { { 2288, 20 }, { 1113, 20 }, { 5514, 1 } }; SIM.Fire("BAG_UPDATE_DELAYED"); SIM.Advance(0.5)
L("all set: " .. key(1)); assert(not key(1):find("Conjure") and not key(1):find("stopmacro"))
L("nova: " .. key(2) .. " | poly: " .. key(3) .. " | blink: " .. key(4) .. " | mana: " .. key(5))
assert(key(3):find("@mouseover") and key(5) == "/use [combat] Mana Agate || /cast [combat] Evocation || /use [nocombat] Conjured Fresh Water")
SlashCmdList.TWIZMAGE("main fireball"); assert(key(1):find("Fireball$")); L("main fireball: " .. key(1))
SlashCmdList.TWIZMAGE("fireblast"); assert(not key(1):find("Fire Blast"))
SlashCmdList.TWIZMAGE("armor off"); buffs["Ice Armor"] = nil; SIM.Advance(0.5); SIM.Fire("UNIT_AURA", "player"); SIM.Advance(0.5)
assert(not key(1):find("Armor")); L("armor off: " .. key(1))
-- low level: Fireball only
known = { ["Fireball"] = 133 }; SlashCmdList.TWIZMAGE("main auto")
L("level 1: " .. key(1)); assert(key(1) == "/cast [@target,harm,nodead] Fireball")
-- rune restock
known["Teleport: Stormwind"] = 3561
GetMerchantNumItems = function() return 2 end
GetMerchantItemLink = function(i) return i == 1 and "item:17031" or "item:17032" end
GetMerchantItemInfo = function() return "x", nil, 1000, 1 end
GetItemCount = function() return 1 end
local bought = {}
BuyMerchantItem = function(i, n) bought[#bought + 1] = i .. "x" .. n end
SIM.money = 1000000
SIM.Fire("MERCHANT_SHOW")
L("bought: " .. table.concat(bought, ", ")); assert(#bought == 1 and bought[1] == "1x4")
SlashCmdList.TWIZMAGE("")
