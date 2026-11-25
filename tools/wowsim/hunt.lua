-- TwizHunt: the Shoot / Melee / Pet keys and vendor restock
local L = function(s) SIM.log[#SIM.log + 1] = s end
SIM.class = "HUNTER"
UnitClass = function() return "hunter", "HUNTER" end
local known = { ["Concussive Shot"] = 5116, ["Intimidation"] = 19577, ["Scatter Shot"] = 19503, ["Mongoose Bite"] = 1495, ["Counterattack"] = 19306, ["Kill Command"] = 34026, ["Auto Shot"] = 75, ["Hunter's Mark"] = 1130, ["Serpent Sting"] = 1978, ["Arcane Shot"] = 3044,
  ["Summon Hawk"] = 9001, ["Raptor Strike"] = 2973, ["Aspect of the Hawk"] = 13165, ["Mend Pet"] = 136,
  ["Revive Pet"] = 982, ["Call Pet"] = 883, ["Feed Pet"] = 6991, ["Aspect of the Cheetah"] = 5118 }
C_Spell = C_Spell or {}
C_Spell.GetSpellInfo = function(n) local id = known[n]; return id and { spellID = id, name = n } end
IsPlayerSpell = function(id) for _, v in pairs(known) do if v == id then return true end end return false end
local buffs, pet = {}, { exists = true, hp = 1000, max = 1000, happy = 3, level = 24, dead = false }
C_UnitAuras = C_UnitAuras or {}
C_UnitAuras.GetAuraDataBySpellName = function(u, n) return buffs[u .. n] and { name = n } or nil end
local target = nil
UnitExists = function(u) if u == "pet" then return pet.exists end if u == "target" then return target ~= nil end return u == "player" end
UnitCanAttack = function(a, b) return b == "target" and target == "enemy" end
UnitIsDeadOrGhost = function(u) if u == "pet" then return pet.dead end return false end
UnitHealth = function(u) return u == "pet" and pet.hp or 1000 end
UnitHealthMax = function(u) return u == "pet" and pet.max or 1000 end
GetPetHappiness = function() return pet.happy end
GetPetFoodTypes = function() return "Meat", "Fungus" end
IsMounted = function() return false end
UnitLevel = function(u) return u == "pet" and pet.level or 25 end
local bag = { [0] = { [1] = 4541 } }   -- bread (pet won't eat)
local items = { [4541] = { "Freshly Baked Bread", 5 }, [117] = { "Tough Jerky", 5 }, [2287] = { "Haunch of Meat", 15 } }
C_Container = { GetContainerNumSlots = function(b) return b == 0 and 16 or 0 end,
  GetContainerItemInfo = function(b, s) local id = bag[b] and bag[b][s]; return id and { itemID = id } end }
local realGII = GetItemInfo
GetItemInfo = function(x)
  local id = tonumber(x) or tonumber(tostring(x):match("item:(%d+)"))
  if items[id] then return items[id][1], nil, nil, items[id][2], 1, "Consumable", "Food & Drink", 20 end
  if id == 2512 then return "Rough Arrow", nil, nil, 5, 1, "Projectile", "Arrow", 200 end
  if id == 2515 then return "Sharp Arrow", nil, nil, 15, 10, "Projectile", "Arrow", 200 end
  if id == 2516 then return "Light Shot", nil, nil, 5, 1, "Projectile", "Bullet", 200 end
  if id == 900 then return "Hunting Bow", nil, nil, 10, 5, "Weapon", "Bows", 1 end
  return realGII and realGII(x)
end
GetInventoryItemLink = function(u, slot) return slot == 18 and "item:900" or nil end
local merchant = { 2512, 2515, 2516, 117, 2287, 4541 }
GetMerchantNumItems = function() return #merchant end
GetMerchantItemLink = function(i) return "item:" .. merchant[i] end
GetMerchantItemInfo = function(i) return nil, nil, 10, 1, -1 end
local bought = {}
BuyMerchantItem = function(i, n) bought[#bought + 1] = merchant[i] .. "x" .. n end
GetItemCount = function(id) return id == 2515 and 150 or 0 end
GetMoney = function() return 1e7 end

SIM.LoadAddon(REPO .. "/TwizHunt", "TwizHunt")
SIM.Fire("ADDON_LOADED", "TwizHunt"); SIM.Fire("PLAYER_ENTERING_WORLD"); SIM.Advance(0.5)
local function raw(n) return tostring(TwizHuntButton:GetAttribute("macrotext" .. n)) end
local function key(n)
  -- expand "/click TwizHuntStepN" into that step's macro, so the test reads the whole key
  local t = raw(n):gsub("/click (TwizHuntStep%d+)[^\n]*", function(b) return _G[b]:GetAttribute("macrotext1") end)
  return (t:gsub("\n", " || "))
end
L("no target, all fine: " .. key(1))
target = "enemy"; SIM.Fire("PLAYER_TARGET_CHANGED"); SIM.Advance(0.5)
L("enemy targeted, no Hawk: " .. key(1))
assert(key(1):find("^/cast %[nocombat%] !Aspect of the Hawk || /cast %[@target,harm,nodead%] Raptor Strike") and not key(1):find("stopmacro"), "DBG " .. key(1))
-- every refusable spell is its own /click step; only the aspect and /petattack stay inline
assert(raw(1):find("^/cast %[nocombat%] !Aspect of the Hawk\n/click TwizHuntStep1\n/click TwizHuntStep2\n"), "DBG " .. raw(1))
assert(key(1):find("/castsequence %[@target,harm,nodead%] reset=target/combat !Auto Shot, null || /petattack"), "DBG " .. key(1))
assert(not key(1):find("/cast %[@target,harm,nodead%] !Auto Shot"))
buffs["playerAspect of the Hawk"] = true; SIM.Fire("UNIT_AURA", "player"); SIM.Advance(0.5)
L("with Hawk: " .. key(1))
assert(key(1):find("castsequence %[@target,harm,nodead%] reset=target Hunter's Mark, Summon Hawk, Serpent Sting, null"))
pet.hp = 400; SIM.Fire("UNIT_HEALTH", "pet"); SIM.Advance(0.5)
L("pet at 40%: " .. key(1))
assert(key(1):find("%[nocombat,noharm,@pet%] Mend Pet || /stopmacro %[nocombat,noharm%]"), "DBG " .. key(1))
pet.hp = 1000; pet.happy = 1; bag[0][2] = 117; SIM.Fire("UNIT_HAPPINESS", "pet"); SIM.Advance(0.5)
L("pet unhappy, jerky in bags: " .. key(1))
assert(key(1):find("Feed Pet") and key(1):find("Tough Jerky"))
pet.happy = 3; pet.dead = true; SIM.Fire("UNIT_PET"); SIM.Advance(0.5)
L("pet dead: " .. key(1)); assert(key(1):find("%[nocombat%] Revive Pet || /stopmacro %[nocombat%]"), "DBG " .. key(1))
pet.dead = false
L("melee key: " .. key(2))
L("pet key: " .. key(3))
SIM.Fire("MERCHANT_SHOW")
L("vendor bought: " .. table.concat(bought, ", "))
assert(bought[1] == "2515x200" and bought[#bought]:find("^2287x"), "Sharp Arrow topped up, Haunch of Meat for the pet")
assert(key(2):find("/cast %[@target,harm,nodead%] Raptor Strike || /cast %[@target,harm,nodead%] Mongoose Bite || /cast %[@target,harm,nodead%] Counterattack"), "DBG " .. key(2))
assert(key(1):find("Arcane Shot || /cast %[@target,harm,nodead%] Kill Command"), "DBG " .. key(1))
L("hunter reactives in")
SlashCmdList.TWIZHUNT("reactives"); assert(not key(2):find("Mongoose") and not key(1):find("Kill Command"))
L("hunter reactives off")
assert(key(2):find("^/startattack.* || /cast %[combat,@target,harm,nodead%] Intimidation$"), "DBG " .. key(2))
assert(key(1):find(" || /cast %[combat,@target,harm,nodead%] Intimidation$"), "DBG " .. key(1))
assert(not key(1):find("Scatter"))
L("hunter interrupt on both keys: " .. key(2))
assert(key(1):find("null || /cast %[@target,harm,nodead%] Concussive Shot || /cast %[@target,harm,nodead%] Arcane Shot"), "DBG " .. key(1))
L("merged: " .. key(1))
assert(key(1):find("!Auto Shot, null"), "DBG " .. key(1))
assert(key(1):find("^/cast %[@target,harm,nodead%] Raptor Strike || /castsequence.*Arcane Shot || /cast %[combat,@target,harm,nodead%] Intimidation$"), "DBG " .. key(1))
SlashCmdList.TWIZHUNT("melee"); assert(not key(1):find("Raptor")); SlashCmdList.TWIZHUNT("melee"); assert(key(1):find("Raptor"))
L("concussive: " .. key(1))
SlashCmdList.TWIZHUNT("concussive"); assert(not key(1):find("Concussive")); L("concussive off")
