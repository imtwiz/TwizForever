-- TwizHunt: one-key hunter.
--   Shoot key (Options > Keybindings > AddOns > TwizHunt):
--     out of combat it first fixes what's missing - pet dead -> Revive Pet, no pet -> Call Pet,
--     pet hurt -> Mend Pet, pet unhappy -> Feed Pet, and Aspect of the Hawk when you have an enemy
--     targeted (Aspect of the Cheetah with nothing targeted, if you turn that on);
--     then on an enemy: Auto Shot + pet attack, and on each new target Hunter's Mark ->
--     Summon Hawk -> Serpent Sting, then Concussive Shot whenever it's ready (1.3.0: slows the target
--     so it can't close the distance; /hunt concussive turns it off; 1.7.0: it also paces Serpent
--     Sting), then Arcane Shot - and when
--     the target is in melee range, Raptor Strike (+ Mongoose Bite / Counterattack when allowed)
--     on the same key (1.4.0; each half is simply refused by the game at the wrong range).
--     1.5.0: Auto Shot is asked for once per target instead of on every press (re-asking while
--     it's shooting delays the shots). 1.6.0: the game ends a press at the first spell it refuses,
--     so Arcane Shot / Raptor Strike / Concussive Shot / reactives / interrupt take turns, one per
--     press, from a rotating button - a refused one costs one press, not the whole key.
--     1.8.0: back to single-spell rotating steps (1.7.x's step macros never ran in this game);
--     /hunt debug + /hunt log record what each press does. 1.8.1: Serpent Sting follows
--     Concussive Shot each time it's off its 12 s cooldown (the key's last line). 1.8.2: no
--     "null" in sequences - this game's sequence code errors on it and aborts the press.
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
    petFood = true, petFoodCount = 20, mendAt = 0.6, reactives = true, concussive = true, meleeMerge = true, debug = true }

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
    -- returns: lines, label, the conditions under which the press stops there
    if st == "dead" and Known("Revive Pet") then return "/cast Revive Pet", "Revive Pet", "nocombat" end
    if st == "missing" and Known("Call Pet") then return "/cast Call Pet", "Call Pet", "nocombat" end
    -- 1.4.0: mending / feeding only with no enemy targeted, so targeting one always shoots
    if st == "hurt" and Known("Mend Pet") then return "/cast [@pet] Mend Pet", "Mend Pet", "nocombat,noharm" end
    if st == "unhappy" and Known("Feed Pet") then
        local food = BagFood()
        if food then return "/cast Feed Pet\n/use " .. food, "Feed Pet (" .. food .. ")", "nocombat,noharm" end
    end
end
local function AspectFix()
    if not (db and db.aspects) or IsMounted and IsMounted() then return nil end
    local enemy = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDeadOrGhost("target")
    if enemy and Known("Aspect of the Hawk") and not HasBuff("player", "Aspect of the Hawk") then
        return "/cast !Aspect of the Hawk", "Aspect of the Hawk"
    end
    if not enemy and db.cheetah and Known("Aspect of the Cheetah") and not HasBuff("player", "Aspect of the Cheetah") then
        return "/cast !Aspect of the Cheetah", "Aspect of the Cheetah"
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

-- 1.6.0: in this game the first spell it refuses (on cooldown, out of range, too close) ends the
-- whole key press - nothing after it runs. So the spells that can be refused take turns instead:
-- a rotating spell button casts the NEXT spell of its list on each press (restricted code, like
-- TwizHeal's combat combo, which works in this game). A refused one costs that one press; spam
-- the key and every spell gets its turn several times a second.
-- 1.8.0: back to spell buttons - 1.7.x's small step macros never ran in this game.
local cycles, header = {}, nil
local function CycleButton(name, spells)
    if not (SecureHandlerWrapScript and CreateFrame) then return nil end
    local b = cycles[name]
    if not b then
        if not header then header = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate") end
        b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "spell")
        b:SetAttribute("unit", "target")
        b:Hide()
        local ok = pcall(SecureHandlerWrapScript, b, "OnClick", header, [[
            local count = self:GetAttribute("cyclecount") or 0
            if count < 1 then return end
            local n = (self:GetAttribute("cyclen") or 0) % count + 1
            self:SetAttribute("cyclen", n)
            self:SetAttribute("spell", self:GetAttribute("cyclespell" .. n))
        ]])
        if not ok then return nil end
        cycles[name] = b
        if NS.Watch then NS.Watch(b) end
    end
    local list = table.concat(spells, ",")
    if b:GetAttribute("cyclelist") ~= list then
        b:SetAttribute("cyclelist", list)
        for i, sp in ipairs(spells) do b:SetAttribute("cyclespell" .. i, sp) end
        b:SetAttribute("cyclecount", #spells)
        b:SetAttribute("cyclen", 0)
    end
    return b
end

local function ClickLine(b)
    local keyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    -- /click must match the "cast on key down" option, or the button ignores it
    return "/click [@target,harm,nodead] " .. b:GetName() .. (keyDown and " LeftButton 1" or "")
end

local T = "[@target,harm,nodead]"

local function KickSpells(out)
    for l in AutoKick():gmatch("[^\n]+") do
        local sp = l:match("^/cast %b[] (.+)$") or l:match("^/cast (.+)$")
        if sp then out[#out + 1] = sp end
    end
end

local function ShootLines()
    local lines = {}
    -- Auto Shot: asked for out of a fight on every press (the pull). In a fight it isn't asked
    -- for again - asking while it's shooting makes the game retry it and delays the shots (the
    -- stutter). (1.5.0-1.7.0 asked from a /castsequence, which this game refuses - and a refused
    -- line ends the whole press.)
    if Known("Auto Shot") then lines[#lines + 1] = "/cast [nocombat,@target,harm,nodead] !Auto Shot" end
    lines[#lines + 1] = "/petattack " .. T
    -- (1.8.2: no more "/castsequence ..., null" here - this game's sequence code treats "null" as
    -- a spell name, throws a Lua error and aborts the whole press. Hunter's Mark moved into the
    -- timer sequence on the key's last line.)
    -- then the rest take turns, one per press: Arcane Shot, Raptor Strike (in melee range),
    -- reactives, Kill Command, the interrupt
    local list = {}
    local arcane = Known("Arcane Shot") and "Arcane Shot"
    local raptor = db.meleeMerge and Known("Raptor Strike") and "Raptor Strike"
    local function add(x) if x then list[#list + 1] = x end end
    add(arcane); add(raptor)
    if db.meleeMerge and db.reactives then
        for _, r in ipairs({ "Mongoose Bite", "Counterattack" }) do if Known(r) then add(r) end end
    end
    if db.reactives and Known("Kill Command") then add("Kill Command") end
    KickSpells(list)
    local b = #list > 0 and CycleButton("TwizHuntShootCycle", list)
    if b then lines[#lines + 1] = ClickLine(b) end
    -- 1.8.1: Serpent Sting on a timer. The game hides debuffs in a fight and a press-counting list
    -- can't keep time, but cooldowns keep running while you spam: Concussive Shot (12 s cooldown)
    -- goes out whenever it's ready and Serpent Sting (15 s) follows - so it's put back on about
    -- every 12 s. A sequence can't live in a rotating button here, so it's the key's last line.
    -- 1.8.2: Hunter's Mark (and Summon Hawk) lead it on each new target, then the
    -- Concussive -> Serpent pairs repeat five times (about a minute) before Mark comes round again.
    -- No "null" and no "!" in a sequence: this game errors on both.
    local seq = {}
    for _, s in ipairs({ "Hunter's Mark", "Summon Hawk" }) do if Known(s) then seq[#seq + 1] = s end end
    local pair
    if Known("Serpent Sting") then
        if db.concussive and Known("Concussive Shot") then pair = { "Concussive Shot", "Serpent Sting" }
        elseif Known("Arcane Shot") then pair = { "Serpent Sting", "Arcane Shot", "Arcane Shot" }
        else pair = { "Serpent Sting" } end
    elseif db.concussive and Known("Concussive Shot") then
        pair = { "Concussive Shot" }
    end
    if pair then for _ = 1, 5 do for _, sp in ipairs(pair) do seq[#seq + 1] = sp end end end
    if #seq > 0 then
        lines[#lines + 1] = "/castsequence " .. T .. " reset=target " .. table.concat(seq, ", ")
    end
    return lines, list
end

local function MeleeMacro()
    local lines = { "/startattack " .. T, "/petattack " .. T }
    local list = {}
    if Known("Raptor Strike") then list[#list + 1] = "Raptor Strike" end
    if db.reactives then
        for _, r in ipairs({ "Mongoose Bite", "Counterattack" }) do if Known(r) then list[#list + 1] = r end end
    end
    KickSpells(list)
    local b = #list > 0 and CycleButton("TwizHuntMeleeCycle", list)
    if b then lines[#lines + 1] = ClickLine(b) end
    return table.concat(lines, "\n"), list
end
NS.CycleButton = CycleButton

------------------------------------------------------------------------
-- 1.8.0: press log (/hunt debug, /hunt log): what each press tried and what the game answered,
-- kept in TwizHuntDB.log so a fight can be looked at afterwards
------------------------------------------------------------------------
local function Log(msg)
    if not (db and db.debug) then return end
    db.log = db.log or {}
    local ok, line = pcall(string.format, "%.2f %s", GetTime(), msg)
    if not ok then return end
    table.insert(db.log, line)
    while #db.log > 400 do table.remove(db.log, 1) end
end
NS.Log = Log
local function SpellName(id)
    if not id then return "?" end
    local ok, n = pcall(function() return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) end)
    n = ok and plain(n) or nil
    return n or tostring(plain(id) or "?")
end
function NS.Watch(b)
    pcall(b.HookScript, b, "OnClick", function(self, button, down)
        Log(("click %s %s%s -> %s"):format(self:GetName(), tostring(button), down and " down" or "",
            tostring(plain(self:GetAttribute("spell")) or plain(self:GetAttribute("macrotext")) or "-")))
    end)
end
local watch = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "UI_ERROR_MESSAGE", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "PLAYER_TARGET_CHANGED" }) do
    pcall(watch.RegisterEvent, watch, e)
end
watch:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if not (db and db.debug) then return end
    if event:match("^UNIT_SPELLCAST") then
        if a1 ~= "player" then return end
        local id = event == "UNIT_SPELLCAST_SENT" and a4 or a3
        Log(("%s %s"):format(event:gsub("UNIT_SPELLCAST_", ""):lower(), SpellName(id)))
    elseif event == "UI_ERROR_MESSAGE" then
        Log("error: " .. tostring(plain(a2) or "?"))
    else
        Log(event:lower())
    end
end)
NS.Watch(btn)
local function PetMacro()
    local m = PetFix()
    if m then return m end
    if Known("Mend Pet") then return "/cast [@pet,exists,nodead] Mend Pet; Revive Pet" end
    return ""
end

function NS.Update()
    if not db or InCombatLockdown() then return end
    local lines = {}
    local function addFix(fix, cond)
        for l in fix:gmatch("[^\n]+") do
            -- add the conditions to the line's own [conditions] (or give it some)
            l = l:gsub("^(/%a+) %[", "%1 [" .. cond .. ",", 1)
            if not l:find("%[" .. cond) then l = l:gsub("^(/%a+) ", "%1 [" .. cond .. "] ", 1) end
            lines[#lines + 1] = l
        end
    end
    local fix, why, stop = PetFix()
    if fix then
        -- one pet fix per press, out of combat; the press stops there (it takes a cast)
        addFix(fix, stop)
        lines[#lines + 1] = "/stopmacro [" .. stop .. "]"
    else
        -- 1.4.0: the aspect goes up on the same press and the shooting carries on ("!" = never
        -- switches it off if it's already up)
        local afix, awhy = AspectFix()
        if afix then addFix(afix, "nocombat"); why = awhy end
    end
    local shoot, slist = ShootLines()
    for _, l in ipairs(shoot) do lines[#lines + 1] = l end
    NS.shootList = slist
    local m1 = table.concat(lines, "\n")
    if btn:GetAttribute("macrotext1") ~= m1 then btn:SetAttribute("macrotext1", m1) end
    local m2, mlist = MeleeMacro()
    NS.meleeList = mlist
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
    "MERCHANT_SHOW", "PLAYER_MOUNT_DISPLAY_CHANGED", "CVAR_UPDATE" }) do
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
_G["BINDING_NAME_CLICK TwizHuntButton:LeftButton"] = "Shoot (Auto Shot, Mark, Hawk, Sting, Concussive, Arcane; Raptor Strike in melee range; interrupt)"
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
    elseif cmd == "debug" then flip("debug", "press log (kept in your saved settings; /hunt log shows it)")
    elseif cmd == "log" then
        local l = db.log or {}
        if #l == 0 then Print("the press log is empty (/hunt debug turns it on)") end
        for i = math.max(1, #l - 29), #l do Print(l[i]) end
    elseif cmd == "clearlog" then db.log = {}; Print("press log cleared")
    elseif cmd == "melee" then flip("meleeMerge", "Raptor Strike on the Shoot key in melee range")
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
        Print(("aspects %s (cheetah %s), pet care %s, melee on Shoot %s, Concussive Shot %s, reactives %s, ammo %s (%d stacks), pet food %s (%d). Next out-of-combat fix: %s.")
            :format(onoff(db.aspects), onoff(db.cheetah), onoff(db.petCare), onoff(db.meleeMerge), onoff(db.concussive), onoff(db.reactives), onoff(db.ammo), db.ammoStacks or 5,
            onoff(db.petFood), db.petFoodCount or 20, NS.next or "none"))
        if cmd == "" then Print("/hunt aspects | cheetah | pet | melee | concussive | reactives | ammo [stacks] | food [count] | status") end
    else
        Print("/hunt aspects | cheetah | pet | melee | concussive | reactives | ammo [stacks] | food [count] | status")
    end
end
TwizHunt = NS
