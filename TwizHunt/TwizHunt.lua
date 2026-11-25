-- TwizHunt: one-key hunter.
--   Shoot key (Options > Keybindings > AddOns > TwizHunt):
--     out of combat it first fixes what's missing - pet dead -> Revive Pet, no pet -> Call Pet,
--     pet hurt -> Mend Pet, pet unhappy -> Feed Pet, and Aspect of the Hawk when you have an enemy
--     targeted (Aspect of the Cheetah with nothing targeted, if you turn that on);
--     then on an enemy: Auto Shot + pet attack, and on each new target Hunter's Mark ->
--     Summon Hawk -> Serpent Sting, then Concussive Shot whenever it's ready (1.3.0: slows the target
--     so it can't close the distance; /hunt concussive turns it off), then Arcane Shot.
--   Melee key: Raptor Strike + auto attack + pet attack, plus Mongoose Bite (after a dodge) and
--   Counterattack (after you parry) whenever the game allows them. Kill Command (after a crit)
--   is added to the Shoot key once you know it. /hunt reactives turns those off.
--   Pet key: mend / revive / call / feed, whenever.
--   In a fight the Shoot and Melee keys also fire your interrupt (Intimidation / Silencing Shot) when ready.
--   At any vendor: tops up ammo for your ranged weapon and food your pet eats.
-- The game locks keys in combat and hides health and buffs from addons, so in a fight it runs
-- that fixed order (a new target starts it over) - it can't react to what happens mid-fight.
local ADDON, NS = ...
local db
local DEFAULTS = { aspects = true, cheetah = false, petCare = true, ammo = true, ammoStacks = 5,
    petFood = true, petFoodCount = 20, mendAt = 0.6, reactives = true, concussive = true }

local function Print(m) DEFAULT_CHAT_FRAME:AddMessage("|cffabd473TwizHunt|r: " .. tostring(m)) end
local function plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end

------------------------------------------------------------------------
-- spells, buffs, pet
------------------------------------------------------------------------
local function Known(name)
    if not name then return false end
    local id
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        id = ok and info and info.spellID
    elseif GetSpellInfo then
        id = select(7, GetSpellInfo(name))
    end
    if not id then return false end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return false
end
NS.Known = Known

local function HasBuff(unit, name)
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, "HELPFUL")
        if ok then return a ~= nil end
    end
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok or not a then break end
        if plain(a.name) == name then return true end
    end
    return false
end

local function PetState()
    if not UnitExists("pet") then
        if UnitIsDeadOrGhost and IsPetDead and IsPetDead() then return "dead" end
        return "missing"
    end
    if UnitIsDeadOrGhost("pet") then return "dead" end
    local hp, mx = plain(UnitHealth("pet")), plain(UnitHealthMax("pet"))
    if hp and mx and mx > 0 and hp / mx < (db and db.mendAt or 0.6) then return "hurt" end
    if GetPetHappiness then
        local h = plain(GetPetHappiness())
        if h and h < 3 then return "unhappy" end
    end
    return "ok"
end
NS.PetState = PetState

-- which foods your pet eats, matched by name (the game doesn't tell addons an item's diet)
local DIET_WORDS = {
    Meat = { "meat", "jerky", "steak", "rib", "haunch", "flank", "sausage", "mutton", "chop", "wing", "boar", "wolf", "bear", "chicken", "venison", "kebab" },
    Fish = { "fish", "salmon", "trout", "snapper", "catfish", "mackerel", "eel", "smallfish", "bass", "yellowtail", "grouper", "clam" },
    Bread = { "bread", "muffin", "biscuit", "roll", "cake", "cornbread", "pumpernickel", "rye", "loaf" },
    Cheese = { "cheese", "brie", "cheddar", "swiss", "goat" },
    Fruit = { "apple", "banana", "melon", "peach", "plum", "grape", "berry", "berries", "pear", "fruit" },
    Fungus = { "mushroom", "morel", "truffle", "cap", "fungus", "spore" },
}
local function Diets()
    local set = {}
    if GetPetFoodTypes then
        for _, t in ipairs({ GetPetFoodTypes() }) do set[t] = true end
    end
    return set
end
local function PetEats(name, diets)
    if not name then return false end
    local low = name:lower()
    for diet in pairs(diets) do
        for _, w in ipairs(DIET_WORDS[diet] or {}) do if low:find(w, 1, true) then return true end end
    end
    return false
end
NS.PetEats = PetEats

-- a food in your bags your pet eats (the highest level one)
local function BagFood()
    local diets = Diets()
    if not next(diets) or not C_Container then return nil end
    local best, bestLvl
    for bag = 0, 4 do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id then
                local name, _, _, ilvl, _, itype = GetItemInfo(id)
                if name and (itype == "Consumable" or itype == nil) and PetEats(name, diets) then
                    if not bestLvl or (ilvl or 0) > bestLvl then best, bestLvl = name, ilvl or 0 end
                end
            end
        end
    end
    return best
end
NS.BagFood = BagFood

------------------------------------------------------------------------
-- the keys
------------------------------------------------------------------------
local btn = CreateFrame("Button", "TwizHuntButton", UIParent, "SecureActionButtonTemplate")
btn:RegisterForClicks("AnyUp", "AnyDown")
btn:SetAttribute("type", "macro")
btn:Hide()

-- out of combat: the one thing to fix first (nil = nothing)
local function PetFix()
    if not (db and db.petCare) then return nil end
    local st = PetState()
    if st == "dead" and Known("Revive Pet") then return "/cast Revive Pet", "Revive Pet" end
    if st == "missing" and Known("Call Pet") then return "/cast Call Pet", "Call Pet" end
    if st == "hurt" and Known("Mend Pet") then return "/cast [@pet] Mend Pet", "Mend Pet" end
    if st == "unhappy" and Known("Feed Pet") then
        local food = BagFood()
        if food then return "/cast Feed Pet\n/use " .. food, "Feed Pet (" .. food .. ")" end
    end
end
local function AspectFix()
    if not (db and db.aspects) or IsMounted and IsMounted() then return nil end
    local enemy = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDeadOrGhost("target")
    if enemy and Known("Aspect of the Hawk") and not HasBuff("player", "Aspect of the Hawk") then
        return "/cast Aspect of the Hawk", "Aspect of the Hawk"
    end
    if not enemy and db.cheetah and Known("Aspect of the Cheetah") and not HasBuff("player", "Aspect of the Cheetah") then
        return "/cast Aspect of the Cheetah", "Aspect of the Cheetah"
    end
end

-- the shooting part, the same in and out of combat

-- 1.2.0: in a fight the attack key also fires your interrupt on the target whenever it's off
-- cooldown (the game can't tell a macro whether the enemy is casting, so it goes off as soon as
-- it's ready). TwizInterrupt's list and on/off setting when it's installed, else this class's
-- own interrupt. Crowd control that breaks on damage (Gouge, Scatter Shot) is left out.
local FALLBACK_KICKS = { { "Counter Shot" }, { "Silencing Shot" }, { "Intimidation" } }
local function AutoKick()
    local TI = TwizInterrupt
    if TI and TI.AttackLines then return TI.AttackLines() end
    local lines = {}
    for _, e in ipairs(FALLBACK_KICKS) do
        if Known(e[1]) then
            local c = "combat,@target,harm,nodead" .. (e[2] and ("," .. e[2]) or "")
            lines[#lines + 1] = ("/cast [%s] %s"):format(c, e[1])
        end
    end
    if #lines == 0 then return "" end
    return table.concat(lines, "\n") .. "\n"
end
NS.AutoKick = AutoKick

local function ShootLines()
    local lines = {}
    if Known("Auto Shot") then lines[#lines + 1] = "/cast [@target,harm,nodead] !Auto Shot" end
    lines[#lines + 1] = "/petattack [@target,harm,nodead]"
    local seq = {}
    for _, s in ipairs({ "Hunter's Mark", "Summon Hawk", "Serpent Sting" }) do if Known(s) then seq[#seq + 1] = s end end
    -- the openers once per target ("null" stops the sequence there until the target changes)
    if #seq > 0 then
        lines[#lines + 1] = "/castsequence [@target,harm,nodead] reset=target " .. table.concat(seq, ", ") .. ", null"
    end
    -- 1.3.0: Concussive Shot whenever it's ready, to keep the target from reaching you
    if db.concussive and Known("Concussive Shot") then lines[#lines + 1] = "/cast [@target,harm,nodead] Concussive Shot" end
    if Known("Arcane Shot") then lines[#lines + 1] = "/cast [@target,harm,nodead] Arcane Shot" end
    -- 1.1.0: Kill Command is off the global cooldown, so after Arcane Shot it still goes off when allowed
    if db.reactives and Known("Kill Command") then lines[#lines + 1] = "/cast [@target,harm,nodead] Kill Command" end
    return lines
end

local function MeleeMacro()
    local lines = { "/startattack [@target,harm,nodead]", "/petattack [@target,harm,nodead]" }
    -- 1.1.0: reactives first (the game only allows them right after a dodge/parry and skips them
    -- otherwise); Raptor Strike waits for your next swing, so it still goes off on the same press
    if db.reactives then
        for _, r in ipairs({ "Counterattack", "Mongoose Bite" }) do
            if Known(r) then lines[#lines + 1] = "/cast [@target,harm,nodead] " .. r end
        end
    end
    if Known("Raptor Strike") then lines[#lines + 1] = "/cast [@target,harm,nodead] Raptor Strike" end
    return table.concat(lines, "\n")
end

local function PetMacro()
    local m = PetFix()
    if m then return m end
    if Known("Mend Pet") then return "/cast [@pet,exists,nodead] Mend Pet; Revive Pet" end
    return ""
end

function NS.Update()
    if not db or InCombatLockdown() then return end
    local lines = {}
    local kick = AutoKick()
    if kick ~= "" then lines[1] = kick:gsub("\n$", "") end
    local fix, why = PetFix()
    if not fix then fix, why = AspectFix() end
    if fix then
        -- one fix per press, and only out of combat
        for l in fix:gmatch("[^\n]+") do
            -- add "nocombat" to the line's own [conditions] (or give it some)
            l = l:gsub("^(/%a+) %[", "%1 [nocombat,", 1)
            if not l:find("%[nocombat") then l = l:gsub("^(/%a+) ", "%1 [nocombat] ", 1) end
            lines[#lines + 1] = l
        end
        lines[#lines + 1] = "/stopmacro [nocombat]"
    end
    for _, l in ipairs(ShootLines()) do lines[#lines + 1] = l end
    local m1 = table.concat(lines, "\n")
    if btn:GetAttribute("macrotext1") ~= m1 then btn:SetAttribute("macrotext1", m1) end
    local m2 = AutoKick() .. MeleeMacro()
    if btn:GetAttribute("macrotext2") ~= m2 then btn:SetAttribute("macrotext2", m2) end
    local m3 = PetMacro()
    if btn:GetAttribute("macrotext3") ~= m3 then btn:SetAttribute("macrotext3", m3) end
    NS.next = why
end

------------------------------------------------------------------------
-- vendor restock: ammo for your ranged weapon, food your pet eats
------------------------------------------------------------------------
local AMMO_FOR = { Bows = "Arrow", Crossbows = "Arrow", Guns = "Bullet" }
local function WantAmmo()
    local link = GetInventoryItemLink and GetInventoryItemLink("player", 18)
    if not link then return nil end
    local _, _, _, _, _, _, sub = GetItemInfo(link)
    return sub and AMMO_FOR[sub]
end
NS.WantAmmo = WantAmmo

local function MerchantItems()
    local out = {}
    for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
        local link = GetMerchantItemLink(i)
        if link then
            local name, _, _, ilvl, minLvl, itype, sub, stack = GetItemInfo(link)
            local _, _, price, qty, avail = GetMerchantItemInfo(i)
            local id = tonumber(link:match("item:(%d+)"))
            out[#out + 1] = { i = i, id = id, name = name, ilvl = ilvl or 0, min = minLvl or 0, type = itype, sub = sub,
                stack = stack or 20, price = price or 0, qty = qty or 1, avail = avail or -1 }
        end
    end
    return out
end

local function Buy(item, want)
    local have = GetItemCount(item.id) or 0
    local need = want - have
    if need <= 0 then return 0 end
    local bought = 0
    while need > 0 do
        local n = math.min(need, item.stack)
        local cost = item.price / math.max(1, item.qty) * n
        if (GetMoney() or 0) < cost then break end
        BuyMerchantItem(item.i, n)
        bought, need = bought + n, need - n
    end
    return bought
end

function NS.Restock()
    if not db then return end
    local items = MerchantItems()
    local lvl = UnitLevel("player") or 1
    local said = {}
    -- ammo: the best one you can use for your weapon
    local kind = db.ammo and WantAmmo()
    if kind then
        local best
        for _, it in ipairs(items) do
            if it.type == "Projectile" and it.sub == kind and it.min <= lvl and (not best or it.ilvl > best.ilvl) then best = it end
        end
        if best then
            local n = Buy(best, (db.ammoStacks or 5) * (best.stack or 200))
            if n > 0 then said[#said + 1] = ("%d %s"):format(n, best.name) end
        end
    end
    -- pet food: the highest level food it eats that's not above your pet
    if db.petFood and UnitExists("pet") then
        local diets, plvl = Diets(), UnitLevel("pet") or lvl
        local best
        for _, it in ipairs(items) do
            if it.type == "Consumable" and it.min <= plvl and PetEats(it.name, diets) and (not best or it.ilvl > best.ilvl) then best = it end
        end
        if best then
            local n = Buy(best, db.petFoodCount or 20)
            if n > 0 then said[#said + 1] = ("%d %s"):format(n, best.name) end
        end
    end
    if #said > 0 then Print("bought " .. table.concat(said, " and ") .. ".") end
end

------------------------------------------------------------------------
-- events, slash command
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "UNIT_PET", "UNIT_AURA",
    "UNIT_HEALTH", "PET_UI_UPDATE", "UNIT_HAPPINESS", "BAG_UPDATE_DELAYED", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED",
    "MERCHANT_SHOW", "PLAYER_MOUNT_DISPLAY_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local queued
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        TwizHuntDB = TwizHuntDB or {}
        db = TwizHuntDB
        for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
        NS.db = db
        return
    end
    if not db then return end
    if select(2, UnitClass("player")) ~= "HUNTER" then return end
    if event == "MERCHANT_SHOW" then pcall(NS.Restock); return end
    if (event == "UNIT_AURA" or event == "UNIT_HEALTH") and a1 ~= "player" and a1 ~= "pet" then return end
    if event == "PLAYER_ENTERING_WORLD" and not db.told then
        db.told = true
        Print("bind your keys in Options > Keybindings > AddOns > TwizHunt: Shoot (one key does it all), Melee, Pet care. /hunt for settings.")
    end
    -- batch bursts of events into one update
    if queued then return end
    queued = true
    C_Timer.After(0.1, function() queued = false; NS.Update() end)
end)

_G["BINDING_HEADER_TWIZHUNT"] = "TwizHunt"
_G["BINDING_NAME_CLICK TwizHuntButton:LeftButton"] = "Shoot (Auto Shot, Mark, Hawk, Sting, Concussive, Arcane + interrupt)"
_G["BINDING_NAME_CLICK TwizHuntButton:RightButton"] = "Melee (Raptor Strike, Mongoose Bite, Counterattack + interrupt)"
_G["BINDING_NAME_CLICK TwizHuntButton:MiddleButton"] = "Pet care (mend / revive / call / feed)"

local function onoff(v) return v and "on" or "off" end
SLASH_TWIZHUNT1 = "/hunt"
SLASH_TWIZHUNT2 = "/twizhunt"
SlashCmdList["TWIZHUNT"] = function(msg)
    local cmd, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    local function flip(k, label) db[k] = not db[k]; Print(label .. " " .. onoff(db[k])); NS.Update() end
    if cmd == "aspects" then flip("aspects", "automatic Aspect of the Hawk")
    elseif cmd == "cheetah" then flip("cheetah", "Aspect of the Cheetah when nothing's targeted")
    elseif cmd == "pet" then flip("petCare", "pet care on the Shoot key")
    elseif cmd == "concussive" then flip("concussive", "Concussive Shot whenever it's ready")
    elseif cmd == "reactives" then flip("reactives", "Mongoose Bite / Counterattack / Kill Command when allowed")
    elseif cmd == "ammo" then
        local n = tonumber(rest)
        if n then db.ammoStacks = math.max(0, math.floor(n)); Print(("keeping %d stacks of ammo."):format(db.ammoStacks))
        else flip("ammo", "ammo restock at vendors") end
    elseif cmd == "food" then
        local n = tonumber(rest)
        if n then db.petFoodCount = math.max(0, math.floor(n)); Print(("keeping %d pet food."):format(db.petFoodCount))
        else flip("petFood", "pet food restock at vendors") end
    elseif cmd == "status" or cmd == "" then
        Print(("aspects %s (cheetah %s), pet care %s, Concussive Shot %s, reactives %s, ammo %s (%d stacks), pet food %s (%d). Next out-of-combat fix: %s.")
            :format(onoff(db.aspects), onoff(db.cheetah), onoff(db.petCare), onoff(db.concussive), onoff(db.reactives), onoff(db.ammo), db.ammoStacks or 5,
            onoff(db.petFood), db.petFoodCount or 20, NS.next or "none"))
        if cmd == "" then Print("/hunt aspects | cheetah | pet | concussive | reactives | ammo [stacks] | food [count] | status") end
    else
        Print("/hunt aspects | cheetah | pet | concussive | reactives | ammo [stacks] | food [count] | status")
    end
end
TwizHunt = NS
