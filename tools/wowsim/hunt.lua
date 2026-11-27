-- TwizHunt: the Shoot / Melee / Pet keys and vendor restock
local L = function(s) SIM.log[#SIM.log + 1] = s end
SIM.class = "HUNTER"
UnitClass = function() return "hunter", "HUNTER" end
local known = { ["Concussive Shot"] = 5116, ["Intimidation"] = 19577, ["Scatter Shot"] = 19503, ["Mongoose Bite"] = 1495, ["Counterattack"] = 19306, ["Kill Command"] = 34026, ["Auto Shot"] = 75, ["Hunter's Mark"] = 1130, ["Serpent Sting"] = 1978, ["Arcane Shot"] = 3044,
  ["Summon Hawk"] = 9001, ["Raptor Strike"] = 2973, ["Wing Clip"] = 2974, ["Aspect of the Hawk"] = 13165, ["Mend Pet"] = 136,
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
local realGII = C_Item.GetItemInfo
FakeGII = function(x)
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
FakeMII = function(i) return nil, nil, 10, 1, -1 end
GetMerchantItemID = function(i) return merchant[i] end
GetMerchantItemMaxStack = function(i) return select(8, FakeGII(merchant[i])) or 20 end
-- like this client: GetMerchantItemInfo errors, C_MerchantFrame.GetItemInfo works
C_MerchantFrame = C_MerchantFrame or {}
C_MerchantFrame.GetItemInfo = function(i) local _, _, p, q, a = FakeMII(i) return { price = p, stackCount = q, numAvailable = a, hasExtendedCost = false } end
GetMerchantItemInfo = function() error("attempt to call a nil value") end
local bought = {}
BuyMerchantItem = function(i, n) bought[#bought + 1] = merchant[i] .. "x" .. (n or "bundle") end
GetItemCount = function(id) return id == 2515 and 150 or 0 end
GetMoney = function() return 1e7 end

-- like this client: the global errors, C_Item.GetItemInfo / GetItemCount work
C_Item.GetItemInfo = function(...) return FakeGII(...) end
C_Item.GetItemCount = function(...) return GetItemCount(...) end
GetItemInfo = function() error("attempt to call a nil value") end

SecureHandlerWrapScript = function(frame, script, header, pre) frame.__pre = pre end
local function press(b)  -- run the restricted pre-click snippet, return the spell it set
  local f = assert(loadstring("local self = ...\n" .. b.__pre)); f(b); return b:GetAttribute("spell")
end
SIM.LoadAddon(REPO .. "/TwizHunt", "TwizHunt")
SIM.Fire("ADDON_LOADED", "TwizHunt"); SIM.Fire("PLAYER_ENTERING_WORLD"); SIM.Advance(0.5)
local function raw(n) return tostring(TwizHuntButton:GetAttribute("macrotext" .. n)) end
local function key(n)
  -- expand "/click TwizHuntStepN" into that step's macro, so the test reads the whole key
  local t = raw(n):gsub("/click (%b[]) (TwizHunt%a+Cycle)[^\n]*", function(c, b)
    local f = _G[b]; assert(f:GetAttribute("type") == "spell" and f:GetAttribute("unit") == "target")
    local l = {}
    for i = 1, f:GetAttribute("cyclecount") do l[i] = f:GetAttribute("cyclespell" .. i) end
    return "CYCLE{" .. table.concat(l, " | ") .. "}" end)
  return (t:gsub("\n", " || "))
end
L("no target, all fine: " .. key(1))
target = "enemy"; SIM.Fire("PLAYER_TARGET_CHANGED"); SIM.Advance(0.5)
L("enemy targeted, no Hawk: " .. key(1))
assert(key(1) == "/cast [nocombat] !Aspect of the Hawk || /cast [nocombat,@target,harm,nodead] !Auto Shot || /petattack [@target,harm,nodead] || CYCLE{Arcane Shot | Raptor Strike | Mongoose Bite | Counterattack | Kill Command | Intimidation} || /castsequence [@target,harm,nodead] reset=target Hunter's Mark, Summon Hawk, Concussive Shot, Serpent Sting, Concussive Shot, Serpent Sting, Concussive Shot, Serpent Sting, Concussive Shot, Serpent Sting, Concussive Shot, Serpent Sting", "DBG " .. key(1))
assert(raw(1):find("\n/click %[@target,harm,nodead%] TwizHuntShootCycle\n/castsequence"), "DBG " .. raw(1))
-- each press casts the next spell in the list
local cyc = TwizHuntShootCycle
local got = {}
for i = 1, 13 do got[i] = press(cyc) end
L("presses: " .. table.concat(got, ", "))
assert(got[1] == "Arcane Shot" and got[2] == "Raptor Strike" and got[7] == got[1], "DBG " .. table.concat(got, " | "))


buffs["playerAspect of the Hawk"] = true; SIM.Fire("UNIT_AURA", "player"); SIM.Advance(0.5)
L("with Hawk: " .. key(1))
assert(key(1):find("/petattack %[@target,harm,nodead%] || CYCLE{Arcane Shot"), "DBG " .. key(1))
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
assert(key(2) == "/startattack [@target,harm,nodead] || /petattack [@target,harm,nodead] || CYCLE{Raptor Strike | Wing Clip | Mongoose Bite | Counterattack | Intimidation}", "DBG " .. key(2))
assert(key(1):find("Counterattack | Kill Command | Intimidation} || /castsequence"), "DBG " .. key(1))
L("hunter reactives in")
SlashCmdList.TWIZHUNT("reactives"); assert(not key(2):find("Mongoose") and not key(1):find("Kill Command"))
L("hunter reactives off")
assert(key(2):find("CYCLE{Raptor Strike | Wing Clip | Intimidation}$"), "DBG " .. key(2))
SlashCmdList.TWIZHUNT("wingclip"); assert(key(2):find("CYCLE{Raptor Strike | Intimidation}$"), "DBG " .. key(2)); L("wing clip off: " .. key(2)); SlashCmdList.TWIZHUNT("wingclip")
assert(not key(1):find("Scatter"))
L("merged: " .. key(1))
assert(key(1):find("CYCLE{Arcane Shot | Raptor Strike | Intimidation} || /castsequence %[@target,harm,nodead%] reset=target Hunter's Mark, Summon Hawk, Concussive Shot, Serpent Sting, Concussive Shot"), "DBG " .. key(1))
SlashCmdList.TWIZHUNT("melee"); assert(not key(1):find("Raptor")); L("melee off: " .. key(1)); SlashCmdList.TWIZHUNT("melee"); assert(key(1):find("Raptor"))
SlashCmdList.TWIZHUNT("concussive"); assert(key(1):find("Summon Hawk, Serpent Sting, Arcane Shot, Arcane Shot, Serpent Sting")); L("concussive off: " .. key(1))

SIM.Fire("UNIT_SPELLCAST_SENT", "player", "x", "y", 3044); SIM.Fire("UI_ERROR_MESSAGE", 1, "Out of range.")
SlashCmdList.TWIZHUNT("log"); assert(#TwizHuntDB.log >= 2); L("log entries: " .. #TwizHuntDB.log .. " last: " .. TwizHuntDB.log[#TwizHuntDB.log])

for i = 1, 2 do assert(not key(i):find("null") and not key(i):find("castsequence[^|]*!")) end; L("no null / no ! in any sequence")

-- 1.9.0: with a quiver, buy the best arrows you can use until every quiver slot is full
local quiverItems = { [1] = 2512, [2] = 2512 }   -- 2 slots of Rough Arrow (worse than Sharp Arrow)
GetInventoryItemLink = function(u, slot) if slot == 18 then return "item:900" end if slot == 20 then return "item:7278" end end
local gii2 = FakeGII
FakeGII = function(x)
  local id = tonumber(x) or tonumber(tostring(x):match("item:(%d+)"))
  if id == 7278 then return "Light Leather Quiver", nil, nil, 10, 1, "Quiver", "Quiver", 1 end
  if id == 7279 then return "Small Leather Ammo Pouch", nil, nil, 10, 1, "Quiver", "Ammo Pouch", 1 end
  return gii2(x)
end
C_Container.GetContainerNumSlots = function(b) if b == 0 then return 16 elseif b == 1 then return 12 end return 0 end
C_Container.GetContainerItemInfo = function(b, s)
  local id = (b == 1 and quiverItems[s]) or (bag[b] and bag[b][s]); return id and { itemID = id, stackCount = 200 } end
local said = {}
local realPrint = DEFAULT_CHAT_FRAME.AddMessage
DEFAULT_CHAT_FRAME.AddMessage = function(self, m) said[#said + 1] = m end
bought = {}
SIM.Fire("MERCHANT_SHOW")
local arrows = 0
for _, b in ipairs(bought) do local id, n = b:match("^(%d+)x(%d+)$"); if id == "2515" then arrows = arrows + tonumber(n) end end
L("quiver (12 slots): bought " .. arrows .. " Sharp Arrow: " .. table.concat(bought, ", "))
assert(arrows == 12 * 200 - 150, "fills 12 quiver slots of Sharp Arrow, minus the 150 you have: " .. arrows)
assert(table.concat(said, "\n"):find("2 quiver slots hold Rough Arrow"), "warns about worse ammo taking slots")
-- a gun with an ammo pouch: bullets, sized by the pouch; a quiver doesn't count for a gun
GetInventoryItemLink = function(u, slot) if slot == 18 then return "item:901" end if slot == 20 then return "item:7278" end if slot == 21 then return "item:7279" end end
local gii3 = FakeGII
FakeGII = function(x)
  local id = tonumber(x) or tonumber(tostring(x):match("item:(%d+)"))
  if id == 901 then return "Old Blunderbuss", nil, nil, 10, 1, "Weapon", "Guns", 1 end
  return gii3(x)
end
C_Container.GetContainerNumSlots = function(b) if b == 0 then return 16 elseif b == 1 then return 12 elseif b == 2 then return 8 end return 0 end
quiverItems = {}
bought, said = {}, {}
SIM.Fire("MERCHANT_SHOW")
local shot = 0
for _, b in ipairs(bought) do local id, n = b:match("^(%d+)x(%d+)$"); if id == "2516" then shot = shot + tonumber(n) end end
L("gun + 8-slot pouch: bought " .. shot .. " Light Shot")
assert(shot == 8 * 200, "fills the 8-slot ammo pouch: " .. shot)
-- short on money: buys what it can afford
GetMoney = function() return 10 * 300 end   -- price 10 each -> 300 bullets
bought, said = {}, {}
SIM.Fire("MERCHANT_SHOW")
shot = 0
for _, b in ipairs(bought) do local id, n = b:match("^(%d+)x(%d+)$"); if id == "2516" then shot = shot + tonumber(n) end end
L("short on money: bought " .. shot)
assert(shot == 300, "buys what it can afford: " .. shot)
-- 1.9.1: the best ammo's info isn't loaded the first time the vendor opens -> wait for it, then buy it
GetMoney = function() return 1e7 end
GetInventoryItemLink = function(u, slot) if slot == 18 then return "item:900" end end
local loaded = false
local gii4 = FakeGII
FakeGII = function(x)
  local id = tonumber(x) or tonumber(tostring(x):match("item:(%d+)"))
  if id == 2515 and not loaded then return nil end
  return gii4(x)
end
C_Item.GetItemInfoInstant = function(x)
  local id = tonumber(x) or tonumber(tostring(x):match("item:(%d+)"))
  if id == 2515 or id == 2512 then return id, "Projectile", "Arrow", "", 1, 6, 2 end
  return id, "Consumable", "", "", 1, 0, 0
end
local requested = false
C_Item.RequestLoadItemDataByID = function(id) if id == 2515 then requested = true; C_Timer.After(0.3, function() loaded = true end) end end
MerchantFrame.__shown = true
bought, said = {}, {}
SIM.Fire("MERCHANT_SHOW")
assert(#bought == 0 and requested, "waits instead of buying the worse arrow: " .. table.concat(bought, ", "))
SIM.Advance(2)
L("after item info loaded: " .. table.concat(bought, ", "))
assert(bought[1] == "2515x200", "bought Sharp Arrow once it loaded: " .. table.concat(bought, ", "))
for _, b in ipairs(bought) do assert(not b:find("^2512x"), "never Rough Arrow") end
assert(table.concat(TwizHuntDB.log, "\n"):find("%-> Sharp Arrow"), "choice is in the log")
-- /hunt buy re-runs it
bought = {}
GetItemCount = function(id) return 0 end
SlashCmdList.TWIZHUNT("buy")
assert(bought[1] == "2515x200", "/hunt buy: " .. table.concat(bought, ", "))
L("/hunt buy: " .. #bought .. " purchases")
-- 1.9.3: ammo sold in bundles of 200 -> one BuyMerchantItem(i) per bundle, no quantity
FakeMII = function(i) if merchant[i] == 2515 then return nil, nil, 2000, 200, -1 end return nil, nil, 10, 1, -1 end
GetItemCount = function(id) return id == 2515 and 150 or 0 end
bought = {}
SlashCmdList.TWIZHUNT("buy")
local bundles = 0
for _, b in ipairs(bought) do if b == "2515xbundle" then bundles = bundles + 1 end assert(not b:find("^2515x%d")) end
L("bundles of 200: " .. bundles .. " purchases (" .. table.concat(bought, ", ") .. ")")
assert(bundles == 5, "1000 wanted, 150 held -> 5 bundles: " .. bundles)
-- bundles you can't afford aren't bought
GetMoney = function() return 2000 * 2 + 5 end
bought = {}
SlashCmdList.TWIZHUNT("buy")
bundles = 0
for _, b in ipairs(bought) do if b == "2515xbundle" then bundles = bundles + 1 end end
assert(bundles == 2, "money for 2 bundles: " .. bundles)
DEFAULT_CHAT_FRAME.AddMessage = realPrint
