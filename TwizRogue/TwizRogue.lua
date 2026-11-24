-- TwizRogue: one-key rogue.
--   Attack key (Options > Keybindings > AddOns > TwizRogue):
--     out of combat it first puts poison on a weapon that has none (one weapon per press);
--     /rogue stealth: with an enemy targeted and not in Stealth, it stealths first (off by default:
--     while Stealth is on cooldown that would hold the key back);
--     in Stealth: the opener - Ambush with a dagger in your main hand, else Cheap Shot (/rogue opener
--     garrote|cheap|ambush to choose) - without breaking Stealth by auto attacking;
--     then auto attack and, per target: builder x3 -> Eviscerate (builder = Mutilate once you
--     know it and hold daggers, else Sinister Strike; /rogue snd adds Slice and Dice after the first).
--   Interrupt key: Kick (Shift: Gouge).
--   At vendors: tops up Flash Powder (once you know Vanish) and poisons the vendor sells.
-- The game locks keys in combat and hides combo points' effect on macros, so the order is fixed: a
-- sequence only moves on when a cast actually goes off (not enough energy = it waits).
local ADDON, NS = ...
local db
local DEFAULTS = { poisons = true, stealth = false, opener = "auto", snd = false, restock = true, powder = 10, poisonCount = 10 }

local function Print(m) DEFAULT_CHAT_FRAME:AddMessage("|cfffff569TwizRogue|r: " .. tostring(m)) end
local function plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end

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

local function WeaponType(slot)
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    if not link then return nil end
    return select(7, GetItemInfo(link))
end

------------------------------------------------------------------------
-- poisons
------------------------------------------------------------------------
local MAIN_POISONS = { "Instant Poison", "Deadly Poison", "Wound Poison", "Crippling Poison" }
local OFF_POISONS = { "Deadly Poison", "Instant Poison", "Crippling Poison", "Mind-numbing Poison", "Wound Poison" }

-- the highest rank of a poison in your bags: "Instant Poison II" beats "Instant Poison"
local function BagPoison(order)
    if not C_Container then return nil end
    local found = {}
    for bag = 0, 4 do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            local name, ilvl
            if id then name, _, _, ilvl = GetItemInfo(id) end
            if name then
                for _, base in ipairs(order) do
                    if name == base or name:find("^" .. base:gsub("%-", "%%-") .. " [IVX]+$") then
                        if not found[base] or (ilvl or 0) > found[base].ilvl then found[base] = { name = name, ilvl = ilvl or 0 } end
                    end
                end
            end
        end
    end
    for _, base in ipairs(order) do if found[base] then return found[base].name end end
end
NS.BagPoison = BagPoison

local function PoisonFix()
    if not (db and db.poisons) or not GetWeaponEnchantInfo then return nil end
    local hasMain, _, _, _, hasOff = GetWeaponEnchantInfo()
    if not plain(hasMain) and GetInventoryItemLink("player", 16) then
        local p = BagPoison(MAIN_POISONS)
        if p then return { "/use " .. p, "/use 16" }, p .. " on your main hand" end
    end
    local off = WeaponType(17)
    if not plain(hasOff) and off and off ~= "Shields" and off ~= "Miscellaneous" then
        local p = BagPoison(OFF_POISONS)
        if p then return { "/use " .. p, "/use 17" }, p .. " on your off hand" end
    end
end

------------------------------------------------------------------------
-- the keys
------------------------------------------------------------------------
local btn = CreateFrame("Button", "TwizRogueButton", UIParent, "SecureActionButtonTemplate")
btn:RegisterForClicks("AnyUp", "AnyDown")
btn:SetAttribute("type", "macro")
btn:Hide()

local T = "@target,harm,nodead"

local function Opener()
    local choice = db.opener or "auto"
    local dagger = WeaponType(16) == "Daggers"
    if choice == "garrote" and Known("Garrote") then return "Garrote" end
    if choice == "cheap" and Known("Cheap Shot") then return "Cheap Shot" end
    if choice == "ambush" and Known("Ambush") then return "Ambush" end
    if dagger and Known("Ambush") then return "Ambush" end
    if Known("Cheap Shot") then return "Cheap Shot" end
    if Known("Garrote") then return "Garrote" end
    return "Sinister Strike"
end

local function Builder()
    if Known("Mutilate") and WeaponType(16) == "Daggers" then return "Mutilate" end
    return "Sinister Strike"
end

local function AttackMacro()
    local lines = {}
    local fix, why = PoisonFix()
    if fix then
        for _, l in ipairs(fix) do lines[#lines + 1] = l:gsub("^/use ", "/use [nocombat] ", 1) end
        lines[#lines + 1] = "/stopmacro [nocombat]"
    end
    -- Stealth up first (out of combat, on an enemy), then the opener without breaking it
    if db.stealth and Known("Stealth") then
        lines[#lines + 1] = ("/cast [nostealth,nocombat,%s] Stealth"):format(T)
        lines[#lines + 1] = ("/stopmacro [nostealth,nocombat,%s]"):format(T)
    end
    if Known("Stealth") then
        lines[#lines + 1] = ("/cast [stealth,%s] %s"):format(T, Opener())
        lines[#lines + 1] = "/stopmacro [stealth]"
    end
    lines[#lines + 1] = ("/startattack [%s]"):format(T)
    local b = Builder()
    -- three builders, then the finisher (with Slice and Dice: right after the first builder)
    local seq = { b }
    if db.snd and Known("Slice and Dice") then seq[#seq + 1] = "Slice and Dice" end
    seq[#seq + 1] = b; seq[#seq + 1] = b
    if Known("Eviscerate") then seq[#seq + 1] = "Eviscerate" end
    lines[#lines + 1] = ("/castsequence [%s] reset=target %s"):format(T, table.concat(seq, ", "))
    return table.concat(lines, "\n"), why
end

local function InterruptMacro()
    if Known("Gouge") and Known("Kick") then return ("/cast [mod:shift,%s] Gouge; [%s] Kick"):format(T, T) end
    if Known("Kick") then return ("/cast [%s] Kick"):format(T) end
    if Known("Gouge") then return ("/cast [%s] Gouge"):format(T) end
    return ""
end

function NS.Update()
    if not db or InCombatLockdown() then return end
    local m1, why = AttackMacro()
    if btn:GetAttribute("macrotext1") ~= m1 then btn:SetAttribute("macrotext1", m1) end
    local m2 = InterruptMacro()
    if btn:GetAttribute("macrotext2") ~= m2 then btn:SetAttribute("macrotext2", m2) end
    NS.next = why
end

------------------------------------------------------------------------
-- vendor restock: Flash Powder (Vanish) and poisons the vendor sells
------------------------------------------------------------------------
function NS.Restock()
    if not (db and db.restock) then return end
    local said = {}
    for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
        local link = GetMerchantItemLink(i)
        local name, minLvl, stack
        if link then name, _, _, _, minLvl, _, _, stack = GetItemInfo(link) end
        local _, _, price, qty = GetMerchantItemInfo(i)
        local want
        if name == "Flash Powder" and Known("Vanish") then want = db.powder or 10
        elseif name and (minLvl or 0) <= (UnitLevel("player") or 1) then
            for _, base in ipairs(OFF_POISONS) do
                if name == base or name:find("^" .. base:gsub("%-", "%%-") .. " [IVX]+$") then
                    -- only the poisons you already use (one of them is in your bags)
                    if (GetItemCount(link) or 0) > 0 then want = db.poisonCount or 10 end
                end
            end
        end
        if want then
            local need = want - (GetItemCount(link) or 0)
            local per = (price or 0) / math.max(1, qty or 1)
            if need > 0 and (GetMoney() or 0) >= per * need then
                local n = need
                while n > 0 do local k = math.min(n, stack or 20); BuyMerchantItem(i, k); n = n - k end
                said[#said + 1] = ("%d %s"):format(need, name)
            end
        end
    end
    if #said > 0 then Print("bought " .. table.concat(said, " and ") .. ".") end
end

------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "UNIT_INVENTORY_CHANGED",
    "BAG_UPDATE_DELAYED", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "MERCHANT_SHOW", "UPDATE_SHAPESHIFT_FORM" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local queued
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        TwizRogueDB = TwizRogueDB or {}
        db = TwizRogueDB
        for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
        NS.db = db
        return
    end
    if not db or select(2, UnitClass("player")) ~= "ROGUE" then return end
    if event == "MERCHANT_SHOW" then pcall(NS.Restock); return end
    if event == "UNIT_INVENTORY_CHANGED" and a1 ~= "player" then return end
    if event == "PLAYER_ENTERING_WORLD" and not db.told then
        db.told = true
        Print("bind your keys in Options > Keybindings > AddOns > TwizRogue: Attack (one key does it all) and Interrupt. /rogue for settings.")
    end
    if queued then return end
    queued = true
    C_Timer.After(0.1, function() queued = false; NS.Update() end)
end)
-- weapon poison wearing off doesn't fire an event: look every few seconds out of combat
C_Timer.NewTicker(5, function() if db and not InCombatLockdown() and select(2, UnitClass("player")) == "ROGUE" then NS.Update() end end)

_G["BINDING_HEADER_TWIZROGUE"] = "TwizRogue"
_G["BINDING_NAME_CLICK TwizRogueButton:LeftButton"] = "Attack (Stealth, opener, builder -> Eviscerate; poisons out of combat)"
_G["BINDING_NAME_CLICK TwizRogueButton:RightButton"] = "Interrupt (Kick; Shift: Gouge)"

local function onoff(v) return v and "on" or "off" end
SLASH_TWIZROGUE1 = "/rogue"
SLASH_TWIZROGUE2 = "/twizrogue"
SlashCmdList["TWIZROGUE"] = function(msg)
    local cmd, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    local function flip(k, label) db[k] = not db[k]; Print(label .. " " .. onoff(db[k])); NS.Update() end
    if cmd == "poisons" then flip("poisons", "poisons on the Attack key")
    elseif cmd == "stealth" then flip("stealth", "Stealth first on the Attack key")
    elseif cmd == "snd" then flip("snd", "Slice and Dice in the sequence")
    elseif cmd == "restock" then flip("restock", "Flash Powder / poison restock at vendors")
    elseif cmd == "opener" then
        if rest == "ambush" or rest == "cheap" or rest == "garrote" or rest == "auto" then
            db.opener = rest; Print("opener: " .. rest); NS.Update()
        else Print("/rogue opener auto|ambush|cheap|garrote  (auto: Ambush with a dagger, else Cheap Shot)") end
    elseif cmd == "status" or cmd == "" then
        Print(("opener %s, Stealth first %s, poisons %s, Slice and Dice %s, restock %s. Next out-of-combat fix: %s.")
            :format(db.opener, onoff(db.stealth), onoff(db.poisons), onoff(db.snd), onoff(db.restock), NS.next or "none"))
        if cmd == "" then Print("/rogue opener <auto|ambush|cheap|garrote> | stealth | poisons | snd | restock | status") end
    else
        Print("/rogue opener <auto|ambush|cheap|garrote> | stealth | poisons | snd | restock | status")
    end
end
TwizRogue = NS
