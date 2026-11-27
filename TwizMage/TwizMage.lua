-- TwizMage: one-key mage.
--   Attack key (Options > Keybindings > AddOns > TwizMage):
--     out of combat it first fixes what's missing, one thing per press - your armor (Ice Armor >
--     Frost Armor, or Mage Armor / Molten Armor if you pick it), and with no enemy targeted it
--     conjures water, food and a mana gem until you have enough;
--     then on an enemy: in a fight Counterspell whenever it's ready (TwizInterrupt), Fire Blast
--     whenever it's ready, otherwise your main nuke - Frostbolt (Fireball before you know it;
--     /mage main fireball | frostbolt | arcane).
--   Frost Nova key, Polymorph key (enemy under the mouse, else your target), Blink key,
--   Mana key: in a fight your mana gem, then Evocation; out of combat drinks your conjured water.
--   At a reagent vendor: tops up Runes of Teleportation / Portals once you know the spells.
-- The game locks keys in combat and hides health, mana and buffs from addons, so in a fight the
-- order is fixed; Fire Blast / Counterspell on cooldown are simply skipped by the game.
local ADDON, NS = ...
-- This client's global GetItemInfo can error ("attempt to call a nil value"); use the C_Item
-- versions when the game has them (looked up on each call)
local function GetItemInfo(x)
    local f = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    if not (f and x) then return nil end
    return f(x)
end
local function GetItemCount(x)
    local f = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
    return f and x and f(x) or 0
end
-- This client's GetMerchantItemInfo errors; C_MerchantFrame.GetItemInfo works.
-- Returns the price and how many units one purchase gives.
local function MerchantPrice(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i)
        if info and not info.hasExtendedCost then return info.price, info.stackCount end
        return nil
    end
    local _, _, price, qty = GetMerchantItemInfo(i)
    return price, qty
end
-- buy `need` units: one purchase per bundle when sold in bundles, else in stack-sized chunks
local function BuyUnits(i, need, qty, stack)
    qty = math.max(1, qty or 1)
    if qty > 1 then
        for _ = 1, math.ceil(need / qty) do BuyMerchantItem(i) end
        return
    end
    local n = need
    while n > 0 do local k = math.min(n, stack or 20); BuyMerchantItem(i, k); n = n - k end
end
local db
local DEFAULTS = { main = "auto", fireblast = true, armor = "auto", conjure = true, water = 20, food = 20,
    gem = true, restock = true, runes = 5 }

local function Print(m) DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0TwizMage|r: " .. tostring(m)) end
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

local function HasBuff(unit, name)
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, "HELPFUL")
        if ok then return a ~= nil end
    end
    return false
end

-- conjured items, lowest to highest rank
NS.WATER = { "Conjured Water", "Conjured Fresh Water", "Conjured Purified Water", "Conjured Spring Water",
    "Conjured Mineral Water", "Conjured Sparkling Water", "Conjured Crystal Water" }
NS.FOOD = { "Conjured Muffin", "Conjured Bread", "Conjured Rye", "Conjured Pumpernickel", "Conjured Sourdough",
    "Conjured Sweet Roll", "Conjured Cinnamon Roll" }
NS.GEMS = { { "Mana Agate", "Conjure Mana Agate" }, { "Mana Jade", "Conjure Mana Jade" },
    { "Mana Citrine", "Conjure Mana Citrine" }, { "Mana Ruby", "Conjure Mana Ruby" } }

-- what's in the bags, by name: counts[name] = n
local function BagCounts()
    local counts = {}
    if not C_Container then return counts end
    for b = 0, 4 do
        for s = 1, (C_Container.GetContainerNumSlots(b) or 0) do
            local info = C_Container.GetContainerItemInfo(b, s)
            if info and info.itemID then
                local name = GetItemInfo(info.itemID)
                if name then counts[name] = (counts[name] or 0) + (info.stackCount or 1) end
            end
        end
    end
    return counts
end

local function Count(counts, list)
    local n, best = 0, nil
    for _, name in ipairs(list) do
        if counts[name] then n = n + counts[name]; best = name end
    end
    return n, best
end

local function Armor()
    local pick = db.armor
    if pick == "off" then return nil end
    if pick == "mage" and Known("Mage Armor") then return "Mage Armor" end
    if pick == "molten" and Known("Molten Armor") then return "Molten Armor" end
    if pick == "frost" and Known("Frost Armor") then return "Frost Armor" end
    if Known("Ice Armor") then return "Ice Armor" end
    if Known("Frost Armor") then return "Frost Armor" end
    return nil
end

local function HaveArmor()
    for _, a in ipairs({ "Frost Armor", "Ice Armor", "Mage Armor", "Molten Armor" }) do
        if HasBuff("player", a) then return a end
    end
end

-- the one out-of-combat fix for this press: macro line, the "stopmacro" conditions, what it's for
local function Fix()
    local armor = Armor()
    if armor and HaveArmor() ~= armor then
        return "/cast [nocombat] " .. armor, "nocombat", armor
    end
    if not db.conjure then return nil end
    local counts = BagCounts()
    -- conjuring takes a few seconds, so only with no enemy targeted (the key works as a "get ready" key)
    if Known("Conjure Water") and Count(counts, NS.WATER) < (db.water or 20) then
        return "/cast [nocombat,noharm] Conjure Water", "nocombat,noharm", "Conjure Water"
    end
    if Known("Conjure Food") and Count(counts, NS.FOOD) < (db.food or 20) then
        return "/cast [nocombat,noharm] Conjure Food", "nocombat,noharm", "Conjure Food"
    end
    if db.gem then
        local have = false
        for _, g in ipairs(NS.GEMS) do if counts[g[1]] then have = true end end
        local best
        for _, g in ipairs(NS.GEMS) do if Known(g[2]) then best = g[2] end end
        if best and not have then
            return "/cast [nocombat,noharm] " .. best, "nocombat,noharm", best
        end
    end
    return nil
end

local function Main()
    local m = db.main
    if m == "fireball" and Known("Fireball") then return "Fireball" end
    if m == "arcane" and Known("Arcane Missiles") then return "Arcane Missiles" end
    if Known("Frostbolt") then return "Frostbolt" end
    if Known("Fireball") then return "Fireball" end
    return nil
end

local T = "@target,harm,nodead"

-- in a fight the attack key also fires Counterspell whenever it's ready (TwizInterrupt's list and
-- on/off setting when it's installed); a macro can't see whether the enemy is casting
local function AutoKick()
    local TI = TwizInterrupt
    if TI and TI.AttackLines then return TI.AttackLines() end
    if Known("Counterspell") then return ("/cast [combat,%s] Counterspell\n"):format(T) end
    return ""
end
NS.AutoKick = AutoKick

local function AttackMacro()
    local lines = {}
    local fix, stop, why = Fix()
    if fix then
        lines[#lines + 1] = fix
        lines[#lines + 1] = "/stopmacro [" .. stop .. "]"
    end
    if db.fireblast and Known("Fire Blast") then lines[#lines + 1] = ("/cast [%s] Fire Blast"):format(T) end
    local m = Main()
    if m then lines[#lines + 1] = ("/cast [%s] %s"):format(T, m) end
    return AutoKick() .. table.concat(lines, "\n"), why
end

local function NovaMacro()
    if Known("Frost Nova") then return "/cast Frost Nova" end
    return ""
end

local function PolyMacro()
    if Known("Polymorph") then return "/cast [@mouseover,harm,nodead][@target,harm,nodead] Polymorph" end
    return ""
end

local function BlinkMacro()
    if Known("Blink") then return "/cast Blink" end
    return ""
end

local function ManaMacro()
    local lines = {}
    local counts = BagCounts()
    local gem
    for _, g in ipairs(NS.GEMS) do if counts[g[1]] then gem = g[1] end end
    if gem then lines[#lines + 1] = "/use [combat] " .. gem end
    if Known("Evocation") then lines[#lines + 1] = "/cast [combat] Evocation" end
    local _, water = Count(counts, NS.WATER)
    if water then lines[#lines + 1] = "/use [nocombat] " .. water end
    return table.concat(lines, "\n")
end

local btn = CreateFrame("Button", "TwizMageButton", UIParent, "SecureActionButtonTemplate")
btn:RegisterForClicks("AnyUp", "AnyDown")
btn:SetAttribute("type", "macro")
btn:Hide()

function NS.Update()
    if not db or InCombatLockdown() then return end
    local m1, why = AttackMacro()
    local set = { m1, NovaMacro(), PolyMacro(), BlinkMacro(), ManaMacro() }
    for i, m in ipairs(set) do
        if btn:GetAttribute("macrotext" .. i) ~= m then btn:SetAttribute("macrotext" .. i, m) end
    end
    NS.next = why
end

------------------------------------------------------------------------
-- reagent vendor: Runes of Teleportation / Portals
------------------------------------------------------------------------
function NS.Restock()
    if not (db and db.restock) then return end
    local tele, portal = false, false
    for _, c in ipairs({ "Stormwind", "Ironforge", "Darnassus", "Exodar", "Orgrimmar", "Undercity", "Thunder Bluff", "Silvermoon" }) do
        if Known("Teleport: " .. c) then tele = true end
        if Known("Portal: " .. c) then portal = true end
    end
    local said = {}
    for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
        local link = GetMerchantItemLink(i)
        local name, stack
        if link then name, _, _, _, _, _, _, stack = GetItemInfo(link) end
        local price, qty = MerchantPrice(i)
        local want
        if name == "Rune of Teleportation" and tele then want = db.runes or 5 end
        if name == "Rune of Portals" and portal then want = db.runes or 5 end
        if want then
            local need = want - (GetItemCount(link) or 0)
            local per = (price or 0) / math.max(1, qty or 1)
            if price and need > 0 and (GetMoney() or 0) >= per * need then
                BuyUnits(i, need, qty, stack)
                said[#said + 1] = ("%d %s"):format(need, name)
            end
        end
    end
    if #said > 0 then Print("bought " .. table.concat(said, " and ") .. ".") end
end

------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "UNIT_AURA",
    "BAG_UPDATE_DELAYED", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "MERCHANT_SHOW" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local queued
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        TwizMageDB = TwizMageDB or {}
        db = TwizMageDB
        for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
        NS.db = db
        return
    end
    if not db or select(2, UnitClass("player")) ~= "MAGE" then return end
    if event == "MERCHANT_SHOW" then pcall(NS.Restock); return end
    if event == "UNIT_AURA" and a1 ~= "player" then return end
    if event == "PLAYER_ENTERING_WORLD" and not db.told then
        db.told = true
        Print("bind your keys in Options > Keybindings > AddOns > TwizMage: Attack (one key does it all), Frost Nova, Polymorph, Blink, Mana. /mage for settings.")
    end
    if queued then return end
    queued = true
    C_Timer.After(0.1, function() queued = false; NS.Update() end)
end)

_G["BINDING_HEADER_TWIZMAGE"] = "TwizMage"
_G["BINDING_NAME_CLICK TwizMageButton:LeftButton"] = "Attack (armor / conjure out of combat; Counterspell, Fire Blast, Frostbolt)"
_G["BINDING_NAME_CLICK TwizMageButton:RightButton"] = "Frost Nova"
_G["BINDING_NAME_CLICK TwizMageButton:MiddleButton"] = "Polymorph (enemy under the mouse, else target)"
_G["BINDING_NAME_CLICK TwizMageButton:Button4"] = "Blink"
_G["BINDING_NAME_CLICK TwizMageButton:Button5"] = "Mana (gem, then Evocation; drink out of combat)"

local function onoff(v) return v and "on" or "off" end
SLASH_TWIZMAGE1 = "/mage"
SLASH_TWIZMAGE2 = "/twizmage"
SlashCmdList["TWIZMAGE"] = function(msg)
    local cmd, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    local function flip(k, label) db[k] = not db[k]; Print(label .. " " .. onoff(db[k])); NS.Update() end
    local usage = "/mage main <auto|frostbolt|fireball|arcane> | armor <auto|frost|ice|mage|molten|off> | fireblast | conjure | water [n] | food [n] | gem | restock | status"
    if cmd == "main" then
        if rest == "auto" or rest == "frostbolt" or rest == "fireball" or rest == "arcane" then
            db.main = rest; Print("main nuke: " .. rest); NS.Update()
        else Print("/mage main auto|frostbolt|fireball|arcane  (auto: Frostbolt, Fireball before you know it)") end
    elseif cmd == "armor" then
        if rest == "auto" or rest == "frost" or rest == "ice" or rest == "mage" or rest == "molten" or rest == "off" then
            db.armor = rest == "ice" and "auto" or rest; Print("armor: " .. rest); NS.Update()
        else Print("/mage armor auto|frost|ice|mage|molten|off  (auto: Ice Armor, else Frost Armor)") end
    elseif cmd == "fireblast" then flip("fireblast", "Fire Blast whenever it's ready")
    elseif cmd == "conjure" then flip("conjure", "conjure water / food / mana gem out of combat")
    elseif cmd == "gem" then flip("gem", "conjure a mana gem")
    elseif cmd == "restock" then flip("restock", "rune restock at reagent vendors")
    elseif cmd == "water" or cmd == "food" then
        local n = tonumber(rest)
        if n then db[cmd] = math.max(0, math.floor(n)); Print(("keeping %d conjured %s."):format(db[cmd], cmd)); NS.Update()
        else Print("/mage " .. cmd .. " <count>") end
    elseif cmd == "status" or cmd == "" then
        Print(("main %s, armor %s, Fire Blast %s, conjure %s (water %d, food %d, gem %s), rune restock %s. Next out-of-combat fix: %s.")
            :format(db.main, db.armor, onoff(db.fireblast), onoff(db.conjure), db.water or 20, db.food or 20,
            onoff(db.gem), onoff(db.restock), NS.next or "none"))
        if cmd == "" then Print(usage) end
    else
        Print(usage)
    end
end
TwizMage = NS
