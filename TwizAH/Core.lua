-- TwizAH: Core - settings, saved data, money helpers and the profit model
local ADDON, ns = ...
TwizAH = ns

BINDING_HEADER_DEPOSITWISE = "TwizAH"
BINDING_NAME_DEPOSITWISE_POSTBEST = "Post next best item"
BINDING_NAME_DEPOSITWISE_POSTMARGINAL = "Post next marginal item (profitable only)"
BINDING_NAME_DEPOSITWISE_POSTALL = "Post All: next item worth posting (best, then marginal)"
BINDING_NAME_DEPOSITWISE_BUYRECIPES = "Buy All Recipes (next one)"
BINDING_NAME_DEPOSITWISE_TOGGLE = "Toggle TwizAH window"
BINDING_NAME_DEPOSITWISE_BUYSUPPLIES = "Buy All Supplies (next step)"
BINDING_NAME_DEPOSITWISE_CANCELUNDERCUT = "Cancel next undercut auction"

-- WoW: Forever uses the classic auction lengths: short 2h, medium 8h, long 24h
ns.DURATION_HOURS = { 2, 8, 24 }
ns.DURATION_LABEL = { [1] = "2h", [2] = "8h", [3] = "24h" }

ns.DEFAULTS = {
    ahCut            = 0.05,           -- auction house cut on a sale
    sellRate         = { 0.30, 0.55, 0.75 }, -- starting guess for 2h/8h/24h; replaced by learned rates as data comes in
    minGain          = 500,            -- copper: AH must beat vendor by at least this much to be worth it (5s)
    fallbackDeposit  = 1,              -- copper: used only if the game won't report a deposit
    dealThreshold    = 0.60,           -- "underpriced" = listing below 60% of the item's median price
    dealMinListings  = 3,              -- need at least this many listings for a median to mean anything
    dealMinProfit    = 500,            -- copper: hide deals making less than this (5s - new server economy)
    dealMinROI       = 0.10,           -- hide deals returning less than 10% on the gold spent
    bidMaxPct        = 0.35,           -- "extremely low bid" = next bid is at most 35% of what the item is worth
    bidIncludeUnknown = false,         -- also show bids on items whose sell speed isn't learned yet
    dealFilter       = "ALL",          -- Deals tab category filter
    quickOnly        = false,          -- Deals tab: only quick flips
    autoScanBags     = true,           -- scan your bags automatically when the AH opens
    autoVendor       = true,           -- sell to merchants anything a vendor pays more for than the AH
    autoFullScan     = true,           -- full AH scan when you open the AH, and every 15 min while it's open
    freshMinutes     = 30,             -- auto-vendor only trusts AH prices this recent
    tooltip          = true,
    wheelPost        = true,
    recipeBudget     = 100000,         -- copper: the most Buy All spends on recipes in total (10g)           -- while the AH is open and items wait, the mouse wheel posts them
}

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function ns.InitDB()
    DepositWiseDB = DepositWiseDB or {}
    local db = DepositWiseDB
    db.settings = db.settings or {}
    CopyDefaults(ns.DEFAULTS, db.settings)
    -- v1.3: new-server minimum profit; move anyone still on the old 10s default
    if (db.settings.version or 0) < 3 then
        if db.settings.dealMinProfit == 1000 then db.settings.dealMinProfit = 500 end
        db.settings.version = 3
    end
    -- v2.2: Forever auctions are 2h/8h/24h (not 12/24/48). Move the starting guesses,
    -- and halve demand learned before scans knew about expiring listings and reposts.
    if db.settings.version < 4 then
        local r = db.settings.sellRate
        if r and r[1] == 0.45 and r[2] == 0.60 and r[3] == 0.75 then db.settings.sellRate = { 0.30, 0.55, 0.75 } end
        for _, x in pairs(db.rates or {}) do if type(x) == "table" and x.u then x.u = x.u * 0.5 end end
        db.settings.version = 4
    end
    db.settings.excluded = db.settings.excluded or {} -- [itemID] = true (exclude) / false (allow)
    db.prices = db.prices or {}   -- [itemID] = { p = lowest unit buyout, t = time }
    db.market = db.market or {}   -- [itemID] = { min, med, n, q, t } from full scans
    db.lastFullScan = db.lastFullScan or 0
    db.history = db.history or {} -- [itemID] = { [yyyymmdd] = { med, q } }
    ns.db = db
    ns.S = db.settings
    ns.Expand(db)
    ns.movers = {}
end

------------------------------------------------------------------------
-- Session tracking
------------------------------------------------------------------------
ns.session = { posts = 0, deposits = 0, postedValue = 0, vendorAvoided = 0, vendored = 0, vendoredGold = 0 }

function ns.StartSession()
    ns.session.start = time()
    ns.session.startMoney = GetMoney()
end

function ns.RecordPost(it, r)
    local s = ns.session
    if not r then return end
    s.posts = s.posts + 1
    s.deposits = s.deposits + (r.deposit or 0)
    s.postedValue = s.postedValue + (r.netIfSold or 0)
    s.vendorAvoided = s.vendorAvoided + (r.vendorTotal or 0)
    if ns.Rates_RecordPost then ns.Rates_RecordPost(it, r) end
end

------------------------------------------------------------------------
-- Saved data is stored compactly (strings) and expanded at login, so the
-- file stays small and the game loads and saves it quickly.
------------------------------------------------------------------------
local function num(x) return tonumber(x) end
local function fmt(x)
    if x == math.floor(x) then return tostring(x) end
    local s = ("%.3f"):format(x)
    s = s:gsub("0+$", "")
    s = s:gsub("%.$", "")
    return s
end

function ns.Expand(db)
    -- history[itemID] = "day:med:q,day:med:q"
    for id, h in pairs(db.history or {}) do
        if type(h) == "string" then
            local t = {}
            for day, med, q in h:gmatch("(%d+):([%d%.]+):([%d%.]+)") do t[num(day)] = { med = num(med), q = num(q) } end
            db.history[id] = t
        end
    end
    -- market[itemID] = "min,med,n,q,t"
    for id, m in pairs(db.market or {}) do
        if type(m) == "string" then
            local a, b, c, d, e = m:match("([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)")
            db.market[id] = { min = num(a), med = num(b), n = num(c), q = num(d), t = num(e) }
        end
    end
    -- rates[itemID] = "u,h,x,n,t"
    for id, r in pairs(db.rates or {}) do
        if type(r) == "string" then
            local u, h, x, n, t = r:match("([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)")
            db.rates[id] = { u = num(u) or 0, h = num(h) or 0, x = num(x) or 0, n = num(n) or 0, t = num(t) }
        end
    end
end

function ns.Compact(db)
    for id, h in pairs(db.history or {}) do
        if type(h) == "table" then
            local parts = {}
            for day, v in pairs(h) do
                if type(v) == "table" and v.med then parts[#parts + 1] = day .. ":" .. fmt(v.med) .. ":" .. fmt(v.q or 0) end
            end
            db.history[id] = (#parts > 0) and table.concat(parts, ",") or nil
        end
    end
    for id, m in pairs(db.market or {}) do
        if type(m) == "table" and m.min then
            db.market[id] = fmt(m.min) .. "," .. fmt(m.med or m.min) .. "," .. (m.n or 0) .. "," .. (m.q or 0) .. "," .. (m.t or 0)
        end
    end
    for id, r in pairs(db.rates or {}) do
        if type(r) == "table" then
            db.rates[id] = fmt(r.u or 0) .. "," .. fmt(r.h or 0) .. "," .. fmt(r.x or 0) .. "," .. (r.n or 0) .. "," .. (r.t or 0)
        end
    end
end

------------------------------------------------------------------------
-- Money helpers
------------------------------------------------------------------------
function ns.Money(copper)
    if copper == nil then return "|cff808080--|r" end
    copper = math.floor(copper + 0.5)
    local neg = copper < 0
    local s = GetMoneyString(math.abs(copper), true)
    if neg then return "|cffff4040-|r" .. s end
    return s
end

-- Parses "1g20s5c", "35s", "250" (copper), "1.5g"
function ns.ParseMoney(text)
    if not text then return nil end
    text = text:lower():gsub("%s", "")
    if text:match("^%d+$") then return tonumber(text) end
    local total, found = 0, false
    for num, unit in text:gmatch("([%d%.]+)([gsc])") do
        found = true
        local n = tonumber(num) or 0
        if unit == "g" then total = total + n * 10000
        elseif unit == "s" then total = total + n * 100
        else total = total + n end
    end
    return found and math.floor(total) or nil
end

function ns.Print(msg)
    print("|cff33ff99TwizAH|r: " .. tostring(msg))
end

------------------------------------------------------------------------
-- Profession tools: you always keep at least one of each kind (the best one
-- you carry). Spare copies may be sold. Tools are never bought from the AH.
------------------------------------------------------------------------
-- tool kinds each item covers
local TOOL_KINDS = {
    [2901] = { "mining" },                 -- Mining Pick
    [5956] = { "smithing" },               -- Blacksmith Hammer
    [7005] = { "skinning" },               -- Skinning Knife
    [6219] = { "wrench" },                 -- Arclight Spanner
    [10498] = { "microadjustor" },         -- Gyromatic Micro-Adjustor
    [4471] = { "fire" },                   -- Flint and Tinder
    [5060] = { "lockpicks" },              -- Thieves' Tools
    [15846] = { "salt" },                  -- Salt Shaker
    [9149] = { "transmute" },              -- Philosopher's Stone
    [40772] = { "mining", "smithing", "skinning", "wrench", "fire" }, -- Gnomish Army Knife
}
for _, id in ipairs({ 6256, 6365, 6366, 6367, 12225, 19022, 19970 }) do TOOL_KINDS[id] = { "fishing" } end
for _, id in ipairs({ 6218, 6339, 11130, 11145, 16207 }) do TOOL_KINDS[id] = { "enchanting" } end
local TOOL_PATTERNS = {
    { "^mining pick$", "mining" }, { "blacksmith hammer", "smithing" },
    { "skinning knife", "skinning" }, { "fishing pole", "fishing" }, { "fishing rod", "fishing" },
    { "arclight spanner", "wrench" }, { "micro%-adjustor", "microadjustor" }, { "^runed .+ rod$", "enchanting" },
    { "^philosopher's stone$", "transmute" }, { "flint and", "fire" }, { "tinderbox", "fire" },
    { "thieves' tools", "lockpicks" }, { "salt shaker", "salt" },
}
local kindCache = {}

-- The tool kinds an item covers, or nil if it isn't a profession tool
function ns.ToolKinds(itemID)
    if not itemID then return nil end
    local cached = kindCache[itemID]
    if cached ~= nil then return cached or nil end
    local kinds = TOOL_KINDS[itemID]
    local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or C_Item.GetItemInfo(itemID)
    if not kinds and name then
        local lname = name:lower()
        if lname == "gnomish army knife" then kinds = TOOL_KINDS[40772] end
        for _, p in ipairs(TOOL_PATTERNS) do
            if not kinds and lname:find(p[1]) then kinds = { p[2] } end
        end
    end
    if not kinds then
        local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
        if classID and Enum.ItemClass and Enum.ItemClass.Profession and classID == Enum.ItemClass.Profession then
            kinds = { "item" .. itemID } -- modern profession tools & accessories: keep one of each
        end
    end
    if name or kinds then kindCache[itemID] = kinds or false end -- cache once the name has loaded
    return kinds
end

function ns.IsTool(itemID) return ns.ToolKinds(itemID) ~= nil end

-- Your /dw exclude list
function ns.IsUserExcluded(itemID)
    local user = itemID and ns.S and ns.S.excluded
    return user and user[itemID] == true or false
end

-- Never bought, bid on or flipped: your exclude list and profession tools
function ns.IsExcluded(itemID)
    if not itemID then return false end
    local user = ns.S and ns.S.excluded
    if user and user[itemID] ~= nil then return user[itemID] end -- your /dw exclude / include wins
    return ns.IsTool(itemID)
end

-- Which bag slots hold the tools you keep: one item per tool kind. A tool you
-- have equipped or soulbound counts first; otherwise the copy that covers the
-- most kinds, then the best quality. Returns { ["bag:slot"] = true }.
function ns.ToolReserve()
    local covered, reserve, spare = {}, {}, {}
    local function cover(kinds) for _, k in ipairs(kinds) do covered[k] = true end end
    for _, invSlot in ipairs({ 16, 17 }) do
        local id = GetInventoryItemID and GetInventoryItemID("player", invSlot)
        local kinds = id and ns.ToolKinds(id)
        if kinds then cover(kinds) end
    end
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local kinds = info and info.itemID and ns.ToolKinds(info.itemID)
            if kinds then
                if info.isBound then cover(kinds)
                else spare[#spare + 1] = { key = bag .. ":" .. slot, kinds = kinds, q = info.quality or 1 } end
            end
        end
    end
    while true do
        local best, bestN
        for _, t in ipairs(spare) do
            if not reserve[t.key] then
                local n = 0
                for _, k in ipairs(t.kinds) do if not covered[k] then n = n + 1 end end
                if n > 0 and (not best or n > bestN or (n == bestN and t.q > best.q)) then best, bestN = t, n end
            end
        end
        if not best then break end
        reserve[best.key] = true
        cover(best.kinds)
    end
    return reserve
end

------------------------------------------------------------------------
-- Quest protection: items your active quests need are never sold
------------------------------------------------------------------------
local questNames = {}   -- [lowercase item name] = quest title

local function ObjectiveItemName(text)
    if not text then return nil end
    -- "Linen Cloth: 3/10"  or  "3/10 Linen Cloth"
    return text:match("^%s*(.-)%s*:%s*%d+%s*/%s*%d+%s*$") or text:match("^%s*%d+%s*/%s*%d+%s+(.-)%s*$")
end

function ns.RefreshQuestItems()
    wipe(questNames)
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local objectives = C_QuestLog.GetQuestObjectives(info.questID)
            for _, o in ipairs(objectives or {}) do
                if o.type == "item" then
                    local name = ObjectiveItemName(o.text)
                    if name and name ~= "" then questNames[name:lower()] = info.title or "a quest" end
                end
            end
        end
    end
end

-- Returns the quest title if an active quest needs this item (or it's a quest-class item)
function ns.QuestNeeds(itemID)
    if not itemID then return nil end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    if classID and Enum.ItemClass and classID == Enum.ItemClass.Questitem then return "quest item" end
    local name = (C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or C_Item.GetItemInfo(itemID)
    return name and questNames[name:lower()]
end

local questEvents = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
    questEvents:RegisterEvent(e)
end
local questPending
questEvents:SetScript("OnEvent", function()
    if questPending then return end
    questPending = true -- QUEST_LOG_UPDATE fires in bursts; refresh once
    C_Timer.After(0.5, function()
        questPending = false
        pcall(ns.RefreshQuestItems)
    end)
end)

------------------------------------------------------------------------
-- Item categories for deal filters
------------------------------------------------------------------------
ns.CATEGORIES = {
    { key = "ALL",       label = "All" },
    { key = "MATS",      label = "Materials", short = "Mats" },
    { key = "GEMS",      label = "Gems" },
    { key = "CLOTH",     label = "Cloth" },
    { key = "METAL",     label = "Metal & Stone", short = "Metal" },
    { key = "HERBS",     label = "Herbs" },
    { key = "LEATHER",   label = "Leather" },
    { key = "ENCHANT",   label = "Enchanting", short = "Ench" },
    { key = "ELEMENTAL", label = "Elemental", short = "Elem" },
    { key = "COOKING",   label = "Cooking", short = "Cook" },
    { key = "FIRSTAID",  label = "First Aid", short = "1st Aid" },
    { key = "ENGINEER",  label = "Engineering", short = "Eng" },
    { key = "GEAR",      label = "Gear" },
}
local MATS = { GEMS = true, CLOTH = true, METAL = true, HERBS = true, LEATHER = true, ENCHANT = true,
    ELEMENTAL = true, COOKING = true, ENGINEER = true, TRADE = true }

-- modern Trade Goods subclasses
local TRADE_SUB = { [1] = "ENGINEER", [2] = "ENGINEER", [3] = "ENGINEER", -- parts, explosives, devices
    [4] = "GEMS", [5] = "CLOTH", [6] = "LEATHER", [7] = "METAL", [8] = "COOKING",
    [9] = "HERBS", [10] = "ELEMENTAL", [12] = "ENCHANT" }
-- consumables: 5 = food & drink, 7 = bandages
local CONSUMABLE_SUB = { [5] = "COOKING", [7] = "FIRSTAID" }
-- profession items recognised by name, whatever their item class
local PROF_RULES = {
    { "FIRSTAID", { "bandage", "anti%-venom" } },
    { "ENGINEER", { "blasting powder", " powder$", " tube$", "modulator", "dynamite", " bomb$", "grenade",
                    " scope$", "mechanical", "gyrochronatom", "gyromatic", "^handful of ", " gizmo$",
                    " widget$", " casing$", " blasting cap", "^unstable trigger", "^thorium shells" } },
    { "COOKING",  { "^raw ", " spices$", "clam meat", "^tender ", " steak$", " tail$", " tongue$" } },
}

local GEM_NAMES = { "malachite", "tigerseye", "shadowgem", "moss agate", "moonstone", "jade", "citrine",
    "aquamarine", "star ruby", "large opal", "blue sapphire", "huge emerald", "azerothian diamond",
    "arcane crystal", "black diamond", "black vitriol", "souldarite", "blood of the mountain" }
local NAME_RULES = {  -- checked in order, lowercase
    { "ENCHANT",   { " dust$", " essence$", " shard$", "^nexus crystal", "^small radiant", "^large radiant" } },
    { "ELEMENTAL", { "^elemental ", "^essence of ", "^heart of fire", "^core of earth", "^breath of wind",
                     "^globe of water", "^ichor of undeath", "^living essence" } },
    { "CLOTH",     { "cloth$", "^bolt of ", "^spider's silk", "silk$", "^felcloth", "^mooncloth" } },
    { "LEATHER",   { "leather$", " hide$", " scale$", "^scale of ", "^devilsaur", "^rugged ", "^thick ", "^heavy " } },
    { "METAL",     { " ore$", " bar$", " stone$", "^thorium", "^mithril", "^truesilver", "^arcanite" } },
    { "COOKING",   { " meat$", " flank$", " ribs$", " snapper$", " salmon$", " eel$", " fish$", " egg$", " wing$", " haunch$" } },
}
local catCache = {}

function ns.ItemCategory(itemID)
    if not itemID then return "OTHER" end
    if catCache[itemID] then return catCache[itemID] end
    local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(itemID)
    local IC = Enum.ItemClass or {}
    local name = (C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or C_Item.GetItemInfo(itemID)
        or (ns.db and ns.db.names and ns.db.names[itemID])
    local lname = name and name:lower()
    local cat
    if lname then
        for _, g in ipairs(GEM_NAMES) do if lname:find(g, 1, true) then cat = "GEMS"; break end end
    end
    if not cat and classID == (IC.Gem or 3) then cat = "GEMS" end
    if not cat and classID == (IC.Tradegoods or 7) then cat = TRADE_SUB[subID] end
    if not cat and classID == (IC.Consumable or 0) then cat = CONSUMABLE_SUB[subID] end
    if not cat and lname and classID ~= (IC.Weapon or 2) and classID ~= (IC.Armor or 4) then
        for _, rule in ipairs(PROF_RULES) do
            for _, p in ipairs(rule[2]) do
                if lname:find(p) then cat = rule[1]; break end
            end
            if cat then break end
        end
    end
    if not cat and lname and (classID == (IC.Tradegoods or 7) or classID == (IC.Reagent or 5) or not classID) then
        for _, rule in ipairs(NAME_RULES) do
            for _, p in ipairs(rule[2]) do
                if lname:find(p) then cat = rule[1]; break end
            end
            if cat then break end
        end
    end
    if not cat then
        if classID == (IC.Tradegoods or 7) or classID == (IC.Reagent or 5) then cat = "TRADE"
        elseif classID == (IC.Weapon or 2) or classID == (IC.Armor or 4) then cat = "GEAR"
        else cat = "OTHER" end
    end
    if classID or name then catCache[itemID] = cat end -- don't cache guesses made before data loaded
    return cat
end

function ns.MatchesCategory(cat, filter)
    if filter == "ALL" then return true end
    if filter == "MATS" then return MATS[cat] or false end
    return cat == filter
end

-- Quick flip: instant (vendor) or the learned sell rate says the whole buy clears within ~24h
function ns.IsQuickFlip(d)
    if d.kind == "VENDOR" then return true end
    if d.kind == "BID" and d.sellVia == "vendor" then return true end
    local sellable = ns.SellableUnits and ns.SellableUnits(d.itemID, 24)
    return sellable ~= nil and sellable >= (d.qty or 1)
end

function ns.ClearHours(d)
    if d.kind == "VENDOR" or (d.kind == "BID" and d.sellVia == "vendor") then return 0 end
    local demand = ns.MarketStats and ns.MarketStats(d.itemID)
    if not demand or demand <= 0 then return nil end
    return (d.qty or 1) / demand
end

local function ItemIDFromText(text)
    return tonumber(text:match("item:(%d+)")) or tonumber(text:match("^%s*(%d+)%s*$"))
end

------------------------------------------------------------------------
-- Price memory
------------------------------------------------------------------------
function ns.RecordPrice(itemID, unit)
    if itemID and unit and unit > 0 then
        if ns.InvalidateCraft then ns.InvalidateCraft() end
        ns.db.prices[itemID] = { p = unit, t = time() }
    end
end

-- Best known lowest unit price for an item: fresh search > full scan
function ns.KnownPrice(itemID)
    local p = ns.db.prices[itemID]
    local m = ns.db.market[itemID]
    if type(p) ~= "table" or not p.t then p = nil end
    if type(m) ~= "table" or not m.t then m = nil end
    if p and m then
        if p.t >= m.t then return p.p, p.t end
        return m.min, m.t
    elseif p then return p.p, p.t
    elseif m then return m.min, m.t end
end

------------------------------------------------------------------------
-- The profit model
--
-- Deposit rules on the modern AH: you pay the deposit when you list.
-- If the item sells, the deposit comes back. If it expires (or you cancel),
-- the deposit is gone and the item comes back to you to relist.
--
-- So for a listing that sells with probability p per attempt and gets
-- relisted until it sells, the expected deposit you lose along the way is
--     deposit * (1 - p) / p
-- and the expected take-home is
--     price * qty * (1 - cut)  -  deposit * (1 - p) / p
-- We compare that for 2h / 8h / 24h against the guaranteed vendor price.
------------------------------------------------------------------------
-- What one extra relist "costs" you in time, used only to pick the listing length:
-- 2% of the sale, at least 10c. With Forever's tiny deposits this stops 2h listings
-- (relist, relist, relist...) from winning on a copper of deposit.
function ns.RelistEffort(net)
    return math.max(10, (net or 0) * (ns.S.relistEffort or 0.02))
end

function ns.Evaluate(it)
    local S = ns.S
    local r = {}
    r.vendorTotal = (it.vendor or 0) * it.qty

    if not it.market then
        r.verdict = it.noListings and "NOLIST" or "NOPRICE"
        return r
    end

    -- Always 1 copper under the cheapest buyout so you're first in line.
    -- If the cheapest listing is already yours, match it (you're already first).
    local post = it.market
    if not it.ownLowest then post = post - 1 end
    if post < 1 then post = 1 end
    r.postUnit = post
    r.gross = post * it.qty
    r.cut = math.floor(r.gross * S.ahCut + 0.5)
    r.netIfSold = r.gross - r.cut

    r.ev, r.lost = {}, {}
    local bestEV, bestDur, bestScore
    for d = 1, 3 do
        local dep = (it.deposit and it.deposit[d]) or S.fallbackDeposit
        local p = (it.rates and it.rates[d]) or S.sellRate[d] or 0.5
        p = math.max(0.01, math.min(1, p))
        r.lost[d] = dep * (1 - p) / p
        r.ev[d] = r.netIfSold - r.lost[d]
        -- choosing the length also weighs your time: every relist is a trip to the AH
        local score = r.ev[d] - (1 / p - 1) * ns.RelistEffort(r.netIfSold)
        if not bestScore or score > bestScore then bestEV, bestDur, bestScore = r.ev[d], d, score end
    end
    r.duration = bestDur
    r.deposit = (it.deposit and it.deposit[bestDur]) or S.fallbackDeposit
    r.depositEstimated = not (it.deposit and it.deposit[bestDur])
    r.bestEV = bestEV
    r.gain = bestEV - r.vendorTotal

    if bestEV <= r.vendorTotal then
        r.verdict = "VENDOR"
    elseif r.gain < S.minGain then
        r.verdict = "MARGINAL"
    else
        r.verdict = "POST"
    end
    return r
end

ns.VERDICT_TEXT = {
    POST     = "|cff40ff40Post|r",
    MARGINAL = "|cffffd100Marginal|r",
    VENDOR   = "|cffff8040Vendor|r",
    NOLIST   = "|cff40c0ffNo comp.|r",
    NOPRICE  = "|cff808080Pending|r",
    POSTED   = "|cff8080ffPosted|r",
}
ns.VERDICT_RANK = { POST = 1, NOLIST = 2, MARGINAL = 3, VENDOR = 4, NOPRICE = 5, POSTED = 6 }

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local HELP = {
    "/dw - toggle the window",
    "/dw scan - rescan your bags (AH must be open)",
    "/dw fullscan - full AH scan for deals (once per 15 min)",
    "/dw buysupplies - Buy All Supplies for profitable crafts (Craft tab; bindable)",
    "/dw recipes - cheapest recipes you are missing; /dw recipemax 10g sets the most Buy All spends (reset clears spent)",
    "/dw postall - post everything worth posting, one item per press",
    "/dw wheel on|off - spin the mouse wheel at the AH to post everything (on by default)",
    "/dw postbest, /dw postmarginal - post the next item (bind keys in Options > Keybindings > AddOns)",
    "/dw cut 5 - AH cut in percent",
"/dw rates 30 55 75 - starting sell chance % for 2h/8h/24h (used until rates are learned)",
    "/dw mingain 5s - AH must beat vendor by at least this",
    "/dw threshold 60 - deals: % of median that counts as underpriced",
    "/dw minprofit 10s, /dw minroi 10 - hide deals below these",
    "/dw bidpct 35 - low bids: max bid as % of item value; /dw bidunknown on|off",
    "/dw filter cloth|gems|metal|herbs|leather|enchanting|elemental|cooking|firstaid|engineering|materials|gear|all, /dw quick on|off",
    "/dw exclude [item] / /dw include [item] - never touch an item (one of each profession tool is always kept)",
    "/dw autoscan on|off, /dw tooltip on|off",
    "/dw autofull on|off - full AH scan on opening the AH and every 15 min while open",
    "/dw auctions - your auctions and undercuts; /dw cancel - cancel next undercut (bindable)",
    "/dw mail - collect gold and items from AH mail (mailbox open)",
    "/dw autovendor on|off - auto-sell items a vendor pays more for (hold Shift at the merchant to skip once)",
    "/dw smelt - smelt your ore into bars, or sell the ore? (also the Smelt tab)",
    "/dw craft - craft with your materials or sell them? plus buy-and-craft profits (Craft tab)",
    "/dw size - reset the window size (drag the bottom-right corner to resize; right-click it to reset too)",
    "/dw settings - show current settings",
}

local function ShowSettings()
    local S = ns.S
    local learned, sold, expired = ns.RatesSummary()
    ns.Print(("undercut 1c, cut %.1f%%, starting sell rates %d/%d/%d%%, min gain %s, deal threshold %d%%"):format(
        S.ahCut * 100,
        S.sellRate[1] * 100, S.sellRate[2] * 100, S.sellRate[3] * 100,
        ns.Money(S.minGain), S.dealThreshold * 100))
    ns.Print(("learned sell rates for %d items; your auctions: %d sold, %d expired"):format(learned, sold, expired))
end

SLASH_DEPOSITWISE1 = "/dw"
SLASH_DEPOSITWISE2 = "/twizah"
SLASH_DEPOSITWISE3 = "/depositwise"
SlashCmdList.DEPOSITWISE = function(msg)
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    local S = ns.S
    if cmd == "" then
        ns.UI.Toggle()
    elseif cmd == "scan" then
        ns.StartBagScan()
    elseif cmd == "buysupplies" then
        ns.BuyAllSupplies()
    elseif cmd == "postall" then
        ns.PostAll()
    elseif cmd == "postmarginal" then
        ns.PostNextMarginal()
    elseif cmd == "postbest" then
        ns.PostNextBest()
    elseif cmd == "recipes" then
        ns.UI.Show(); ns.UI.SetTab("RECIPES")
    elseif cmd == "recipemax" then
        if rest == "reset" then ns.ResetRecipeSpent()
        else
            local t = rest:gsub("%s", "")
            local v = t:match("^%d+$") and tonumber(t) * 10000 or ns.ParseMoney(t)
            if v then ns.SetRecipeBudget(v)
            else ns.Print(("max spend on recipes %s, spent %s. /dw recipemax 10g to change, /dw recipemax reset to clear spent."):format(
                ns.Money(S.recipeBudget or 0), ns.Money(ns.db.recipeSpent or 0))) end
        end
    elseif cmd == "fullscan" then
        ns.StartFullScan()
    elseif cmd == "cut" then
        local n = tonumber(rest); if n then S.ahCut = n / 100 end
        ShowSettings(); ns.UI.Refresh()
    elseif cmd == "rates" then
        local a, b, c = rest:match("(%d+)%s+(%d+)%s+(%d+)")
        if a then S.sellRate = { tonumber(a) / 100, tonumber(b) / 100, tonumber(c) / 100 } end
        ShowSettings(); ns.UI.Refresh()
    elseif cmd == "mingain" then
        local c = ns.ParseMoney(rest); if c then S.minGain = c end
        ShowSettings(); ns.UI.Refresh()
    elseif cmd == "minprofit" then
        local v = ns.ParseMoney(rest); if v then S.dealMinProfit = v end
        ns.BuildDeals(); ns.UI.Refresh(); ns.Print("min deal profit " .. ns.Money(S.dealMinProfit))
    elseif cmd == "minroi" then
        local n = tonumber(rest); if n then S.dealMinROI = n / 100 end
        ns.BuildDeals(); ns.UI.Refresh(); ns.Print(("min deal ROI %d%%"):format(S.dealMinROI * 100))
    elseif cmd == "exclude" or cmd == "include" then
        local id = ItemIDFromText(rest)
        if not id then ns.Print("Usage: /dw " .. cmd .. " [shift-click an item] or item ID"); return end
        S.excluded[id] = (cmd == "exclude")
        ns.Print(("%s will be %s."):format(select(2, C_Item.GetItemInfo(id)) or ("item " .. id),
            cmd == "exclude" and "ignored (never bought, bid on, posted or vendored)" or "included again"))
        ns.BuildDeals(); ns.UI.Refresh()
    elseif cmd == "filter" then
        local want = rest:upper():gsub("%s", "")
        for _, c in ipairs(ns.CATEGORIES) do
            if c.key == want or c.label:upper():gsub("[%s&]", "") == want then S.dealFilter = c.key end
        end
        ns.UI.Refresh(); ns.Print("deal filter: " .. S.dealFilter)
    elseif cmd == "quick" then
        S.quickOnly = rest:lower() ~= "off"; ns.UI.Refresh(); ns.Print("quick flips only: " .. (S.quickOnly and "on" or "off"))
    elseif cmd == "bidpct" then
        local n = tonumber(rest); if n then S.bidMaxPct = n / 100 end
        ns.BuildDeals(); ns.UI.Refresh(); ns.Print(("low bids: bid at most %d%% of value"):format(S.bidMaxPct * 100))
    elseif cmd == "bidunknown" then
        S.bidIncludeUnknown = rest:lower() == "on"; ns.BuildDeals(); ns.UI.Refresh()
        ns.Print("low bids on items with unknown sell speed: " .. (S.bidIncludeUnknown and "shown" or "hidden"))
    elseif cmd == "threshold" then
        local n = tonumber(rest); if n then S.dealThreshold = n / 100 end
        ShowSettings()
    elseif cmd == "autoscan" then
        S.autoScanBags = rest:lower() ~= "off"; ns.Print("auto bag scan " .. (S.autoScanBags and "on" or "off"))
    elseif cmd == "autofull" then
        S.autoFullScan = rest:lower() ~= "off"; ns.Print("automatic full scans " .. (S.autoFullScan and "on" or "off"))
    elseif cmd == "mail" then
        ns.CollectAHMail()
    elseif cmd == "auctions" or cmd == "undercut" then
        ns.UI.Show(); ns.UI.SetTab("AUCTIONS")
    elseif cmd == "cancel" then
        ns.CancelNextUndercut()
    elseif cmd == "wheel" then
        S.wheelPost = rest:lower() ~= "off"
        ns.Print("scroll-to-post " .. (S.wheelPost and "on: spin the mouse wheel to post everything" or "off"))
        if ns.UpdateWheelPost then ns.UpdateWheelPost() end
    elseif cmd == "autovendor" then
        S.autoVendor = rest:lower() ~= "off"; ns.Print("auto-vendor " .. (S.autoVendor and "on" or "off"))
    elseif cmd == "tooltip" then
        S.tooltip = rest:lower() ~= "off"; ns.Print("tooltip " .. (S.tooltip and "on" or "off"))
    elseif cmd == "size" or cmd == "scale" then
        if ns.resetSize then ns.resetSize() else S.sized, S.winW, S.winH, S.scale = nil, nil, nil, nil end
        ns.Print("window size reset (drag the bottom-right corner to resize)")
    elseif cmd == "craft" then
        local list = ns.CraftList()
        if #list == 0 then ns.Print("Nothing yet - open your profession windows once, then scan the AH."); return end
        ns.Print("Craft or sell:")
        for i = 1, math.min(10, #list) do
            print("  " .. (ns.CRAFT_TEXT[list[i].verdict] or "") .. " " .. ns.CraftAdvice(list[i]))
        end
        ns.UI.Show(); ns.UI.SetTab("CRAFT")
    elseif cmd == "smelt" then
        local list = ns.SmeltList()
        if #list == 0 then ns.Print("No ore in your bags and no ore prices known yet."); return end
        ns.Print(ns.smeltFromBags and "Smelt or sell - your ore:" or "Smelt or sell - per 20 ore (none in your bags):")
        for _, c in ipairs(list) do
            local name = C_Item.GetItemInfo(c.ore) or ("item " .. c.ore)
            print(("  %s x%d: %s %s"):format(name, c.qty, ns.SMELT_TEXT[c.verdict] or "", ns.SmeltAdvice(c)))
        end
        ns.UI.Show(); ns.UI.SetTab("SMELT")
    elseif cmd == "settings" then
        ShowSettings()
    else
        for _, line in ipairs(HELP) do ns.Print(line) end
    end
end

------------------------------------------------------------------------
-- Boot
------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_MONEY")
boot:RegisterEvent("PLAYER_LOGOUT")
boot:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_LOGOUT" then
        if ns.db then pcall(ns.Compact, ns.db) end
        return
    end
    if event == "PLAYER_LOGIN" then
        ns.StartSession()
        if ns.BuildMovers then ns.BuildMovers() end
    elseif event == "PLAYER_MONEY" then
        if ns.UI then ns.UI.Refresh() end
    elseif name == ADDON then
        ns.InitDB()
        if ns.Scanner_OnLoad then ns.Scanner_OnLoad() end
        if ns.Tooltip_OnLoad then ns.Tooltip_OnLoad() end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
