-- AutoChef
-- 1) Whenever you open your Cooking window, it remembers every recipe you know
--    and what each one needs (the game only shares recipes while that window
--    is open).
-- 2) When you talk to a vendor, it looks at the ingredients in your bags, works
--    out which recipes they can go into, picks the best recipe for each
--    ingredient (highest level you can eat, with a buff that suits your class
--    and spec), and buys whatever that recipe still needs from this vendor.

local ADDON = ...
local f = CreateFrame("Frame")

local DEFAULTS = {
    enabled     = true,
    confirmOver = 100000, -- copper; ask before spending more than 10g in one visit
    maxCrafts   = 0,      -- 0 = no limit on crafts per recipe
    stats       = nil,    -- manual stat priority override, e.g. {"str","sta"}
    chars       = {},
}

local db, char
local COOKING_SKILL_LINE = 185

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------
local function safe(v)
    if v == nil then return nil end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if ok and secret then return nil end
    end
    return v
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffa040AutoChef:|r " .. msg)
end

local function Money(c)
    if GetMoneyString then return GetMoneyString(c, true) end
    return ("%dg %ds %dc"):format(c / 10000, (c / 100) % 100, c % 100)
end

local function ItemInfo(id)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, link, _, ilvl, reqLevel = get(id)
    return safe(name), safe(link), safe(ilvl), safe(reqLevel)
end

local function RequestItem(id)
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
end

local function BagCount(id)
    local get = (C_Item and C_Item.GetItemCount) or GetItemCount
    return safe(get(id)) or 0
end

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

------------------------------------------------------------------------
-- What does a food do, and does it suit me?
------------------------------------------------------------------------
-- stat key -> words to look for in the item's "Use:" text (lowercased)
local STAT_WORDS = {
    str  = { (ITEM_MOD_STRENGTH_SHORT or "Strength"):lower() },
    agi  = { (ITEM_MOD_AGILITY_SHORT or "Agility"):lower() },
    int  = { (ITEM_MOD_INTELLECT_SHORT or "Intellect"):lower() },
    sta  = { (ITEM_MOD_STAMINA_SHORT or "Stamina"):lower() },
    spi  = { (ITEM_MOD_SPIRIT_SHORT or "Spirit"):lower() },
    ap   = { "attack power" },
    sp   = { "spell damage", "spell power", "damage and healing", "damage done by spells", "magical damage" },
    heal = { "healing" },
    mp5  = { "mana every 5", "mana per 5", "mp5" },
    hp5  = { "health every 5", "health per 5", "hp5" },
    crit = { "critical" },
    hit  = { "chance to hit", "hit rating", " hit by" },
}

local STAT_NAMES = {
    str = "Strength", agi = "Agility", int = "Intellect", sta = "Stamina", spi = "Spirit",
    ap = "Attack Power", sp = "Spell Power", heal = "Healing", mp5 = "Mana regen",
    hp5 = "Health regen", crit = "Crit", hit = "Hit",
}

-- Priorities by class, then by talent tree (tree 1, 2, 3, 4)
local PRIORITY = {
    WARRIOR = { { "str", "sta", "ap", "crit", "hit" }, { "str", "sta", "ap", "crit", "hit" },
                { "sta", "str", "hp5", "agi" } },
    PALADIN = { { "int", "heal", "mp5", "spi" }, { "sta", "str", "hp5", "agi" },
                { "str", "ap", "crit", "sta", "hit" } },
    HUNTER  = { { "agi", "ap", "crit", "hit", "sta" } },
    ROGUE   = { { "agi", "ap", "crit", "hit", "sta" } },
    PRIEST  = { { "heal", "int", "spi", "mp5" }, { "heal", "int", "spi", "mp5" },
                { "sp", "int", "sta", "spi" } },
    SHAMAN  = { { "sp", "int", "mp5", "crit" }, { "agi", "str", "ap", "crit", "sta" },
                { "heal", "int", "mp5", "spi" } },
    MAGE    = { { "sp", "int", "spi", "sta", "crit" } },
    WARLOCK = { { "sp", "sta", "int", "spi" } },
    DRUID   = { { "sp", "int", "spi", "crit" }, { "agi", "str", "sta", "ap", "hp5" },
                { "heal", "int", "spi", "mp5" } },
    DEATHKNIGHT = { { "sta", "str", "hp5" }, { "str", "ap", "crit", "hit" }, { "str", "ap", "crit", "hit" } },
    MONK    = { { "agi", "sta", "hp5" }, { "heal", "int", "spi", "mp5" }, { "agi", "ap", "crit" } },
    DEMONHUNTER = { { "agi", "ap", "crit" }, { "agi", "sta", "hp5" } },
    EVOKER  = { { "sp", "int", "crit" }, { "heal", "int", "mp5" }, { "sp", "int", "crit" } },
}

local function SpecTab()
    if GetSpecialization then
        local ok, s = pcall(GetSpecialization)
        s = ok and safe(s)
        if type(s) == "number" and s > 0 then return s end
    end
    if GetNumTalentTabs and GetTalentTabInfo then
        local best, bestPts = 1, -1
        for tab = 1, (GetNumTalentTabs() or 0) do
            local r = { GetTalentTabInfo(tab) }
            local pts = type(r[5]) == "number" and r[5] or (type(r[3]) == "number" and r[3]) or 0
            if pts > bestPts then best, bestPts = tab, pts end
        end
        return best
    end
    return 1
end

local function MyPriorities()
    if db.stats and #db.stats > 0 then return db.stats, "custom" end
    local _, class = UnitClass("player")
    local list = PRIORITY[class] or { { "sta" } }
    local tab = SpecTab()
    return list[tab] or list[1], (class or "?") .. " tree " .. tab
end

-- Read the buff stats a food gives from its tooltip.
local function FoodStats(itemID)
    local stats = {}
    local text = ""
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local data = C_TooltipInfo.GetItemByID(itemID)
        for _, line in ipairs(data and data.lines or {}) do
            if TooltipUtil and TooltipUtil.SurfaceArgs and not line.leftText then TooltipUtil.SurfaceArgs(line) end
            local t = safe(line.leftText)
            if type(t) == "string" then text = text .. " " .. t:lower() end
        end
    end
    -- Only the part after "Use:" describes the effect.
    local use = (ITEM_SPELL_TRIGGER_ONUSE or "Use:"):lower()
    local at = text:find(use, 1, true)
    if not at then return stats, false end
    local effect = text:sub(at)
    for key, words in pairs(STAT_WORDS) do
        for _, w in ipairs(words) do
            if effect:find(w, 1, true) then stats[key] = true; break end
        end
    end
    -- "damage and healing" is spell power, not a separate healing buff
    if stats.sp and stats.heal and not effect:find("healing done", 1, true)
        and not effect:find("increases healing", 1, true) then stats.heal = nil end
    return stats, true
end

-- Positive = good for me, 0 = no buff (plain food), negative = buff I don't use
local function StatBonus(stats)
    local prio = MyPriorities()
    local pts, any = 0, false
    for key in pairs(stats) do
        any = true
        for rank, want in ipairs(prio) do
            if want == key then pts = pts + math.max(1, 4 - rank); break end
        end
    end
    if not any then return 0 end
    if pts == 0 then return -20 end
    return math.min(pts * 4, 16)
end

local function StatText(stats)
    local t = {}
    for key in pairs(stats) do t[#t + 1] = STAT_NAMES[key] or key end
    table.sort(t)
    return table.concat(t, ", ")
end

------------------------------------------------------------------------
-- Remember recipes while the Cooking window is open
------------------------------------------------------------------------
local function CookingSkillLine()
    if not (GetProfessions and GetProfessionInfo) then return nil end
    local ok, _, _, _, _, cooking = pcall(GetProfessions)
    if not ok or not cooking then return nil end
    local info = { pcall(GetProfessionInfo, cooking) }
    return info[1] and safe(info[8]) or nil
end

local function IsCookingOpen()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo) then return false end
    local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
    if not ok or type(info) ~= "table" then return false end
    if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then return false end
    if C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild() then return false end
    local id = safe(info.professionID)
    local parent = safe(info.parentProfessionID)
    local mine = CookingSkillLine()
    if id == COOKING_SKILL_LINE or parent == COOKING_SKILL_LINE then return true end
    if mine and (id == mine or parent == mine) then return true end
    local name = safe(info.professionName) or safe(info.parentProfessionName)
    return name ~= nil and (name == PROFESSIONS_COOKING or name == "Cooking")
end

local function Capture()
    if not IsCookingOpen() then return end
    local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" or #ids == 0 then return end

    local recipes, n = {}, 0
    for _, raw in ipairs(ids) do
        local id = safe(raw)
        local okR, ri = pcall(C_TradeSkillUI.GetRecipeInfo, id)
        if id and okR and type(ri) == "table" and safe(ri.learned) then
            local okS, sc = pcall(C_TradeSkillUI.GetRecipeSchematic, id, false)
            if okS and type(sc) == "table" and safe(sc.outputItemID) then
                local r = {
                    name = safe(ri.name) or safe(sc.name) or ("Recipe " .. id),
                    out = safe(sc.outputItemID),
                    diff = safe(ri.relativeDifficulty),
                    reagents = {},
                }
                for _, slot in ipairs(sc.reagentSlotSchematics or {}) do
                    if safe(slot.required) ~= false and safe(slot.hiddenInCraftingForm) ~= true then
                        local alts = {}
                        for _, rg in ipairs(slot.reagents or {}) do
                            local rid = safe(rg.itemID)
                            if type(rid) == "number" then alts[#alts + 1] = rid end
                        end
                        local qty = tonumber(safe(slot.quantityRequired)) or 0
                        if #alts > 0 and qty > 0 then
                            r.reagents[#r.reagents + 1] = { ids = alts, qty = qty }
                        end
                    end
                end
                if #r.reagents > 0 then
                    RequestItem(r.out)
                    recipes[id] = r
                    n = n + 1
                end
            end
        end
    end
    if n == 0 then return end
    local before = char.count or 0
    char.recipes, char.count, char.updated = recipes, n, time()
    if n ~= before then Print(("remembered %d cooking recipes."):format(n)) end
end

------------------------------------------------------------------------
-- What the vendor sells
------------------------------------------------------------------------
local function MerchantOffer(i)
    local id = GetMerchantItemID and safe(GetMerchantItemID(i))
    if not id then return nil end
    local info
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        info = C_MerchantFrame.GetItemInfo(i)
    else
        local name, _, price, stack, avail, purchasable, _, ext = GetMerchantItemInfo(i)
        info = { name = name, price = price, stackCount = stack, numAvailable = avail,
                 isPurchasable = purchasable, hasExtendedCost = ext }
    end
    if not info or safe(info.hasExtendedCost) or safe(info.isPurchasable) == false then return nil end
    local avail = safe(info.numAvailable) or -1
    if avail == 0 then return nil end
    local bundle = math.max(1, safe(info.stackCount) or 1)
    local chunk = (GetMerchantItemMaxStack and safe(GetMerchantItemMaxStack(i))) or bundle
    chunk = math.max(bundle, math.floor(chunk / bundle) * bundle)
    return id, { index = i, price = safe(info.price) or 0, bundle = bundle,
                 avail = avail, chunk = chunk, name = safe(info.name) }
end

local function VendorTable()
    local out = {}
    for i = 1, (GetMerchantNumItems() or 0) do
        local id, offer = MerchantOffer(i)
        if id and not out[id] then out[id] = offer end
    end
    return out
end

------------------------------------------------------------------------
-- Planning
------------------------------------------------------------------------
local function ScoreRecipe(r, myLevel)
    local _, _, ilvl, reqLevel = ItemInfo(r.out)
    if not ilvl then RequestItem(r.out) end
    reqLevel = reqLevel or 0
    if reqLevel > myLevel then return nil end      -- can't eat it yet
    local stats, hasUse = FoodStats(r.out)
    local bonus = hasUse and StatBonus(stats) or 0
    local skill = (r.diff == 0 and 2) or (r.diff == 1 and 1) or 0  -- orange / yellow
    -- level decides first; the right buff is worth about 4-16 levels,
    -- a buff you can't use costs 20.
    local score = math.max(reqLevel, (ilvl or 0) - 5) + bonus + skill
    return score, reqLevel, stats, bonus
end

-- Returns plan = { crafts = {...}, buys = { [itemID] = {offer, count, purchases, cost} }, total }
local function BuildPlan(vendor)
    local myLevel = UnitLevel("player") or 1
    local pool = setmetatable({}, { __index = function(t, id) local c = BagCount(id); rawset(t, id, c); return c end })

    local candidates = {}
    for id, r in pairs(char.recipes or {}) do
        local hasBagOnly, ok = false, true
        r.sold = {}
        for i, slot in ipairs(r.reagents) do
            local sold
            for _, rid in ipairs(slot.ids) do if vendor[rid] then sold = rid; break end end
            r.sold[i] = sold
            if not sold then
                hasBagOnly = true
                local have = 0
                for _, rid in ipairs(slot.ids) do have = have + pool[rid] end
                if have < slot.qty then ok = false end
            end
        end
        if ok and hasBagOnly then
            local score, req, stats, bonus = ScoreRecipe(r, myLevel)
            if score then
                candidates[#candidates + 1] = { id = id, r = r, score = score, req = req,
                                                stats = stats, bonus = bonus }
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.r.name < b.r.name
    end)

    local plan = { crafts = {}, buys = {}, total = 0, skipped = {} }
    for _, c in ipairs(candidates) do
        local r = c.r
        local crafts = math.huge
        for i, slot in ipairs(r.reagents) do
            if not r.sold[i] then
                local have = 0
                for _, rid in ipairs(slot.ids) do have = have + pool[rid] end
                crafts = math.min(crafts, math.floor(have / slot.qty))
            end
        end
        if db.maxCrafts > 0 then crafts = math.min(crafts, db.maxCrafts) end
        if crafts ~= math.huge and crafts > 0 then
            local buyList = {}
            for i, slot in ipairs(r.reagents) do
                local need = slot.qty * crafts
                for _, rid in ipairs(slot.ids) do        -- use what's already in bags first
                    local use = math.min(pool[rid], need)
                    pool[rid] = pool[rid] - use
                    need = need - use
                    if need == 0 then break end
                end
                if need > 0 and r.sold[i] then
                    buyList[r.sold[i]] = (buyList[r.sold[i]] or 0) + need
                end
            end
            for vid, n in pairs(buyList) do
                local b = plan.buys[vid] or { offer = vendor[vid], count = 0 }
                b.count = b.count + n
                plan.buys[vid] = b
            end
            plan.crafts[#plan.crafts + 1] = { name = r.name, crafts = crafts, out = r.out,
                                              stats = c.stats, bonus = c.bonus, req = c.req }
        end
    end

    for _, r in pairs(char.recipes or {}) do r.sold = nil end
    for vid, b in pairs(plan.buys) do
        local o = b.offer
        b.purchases = math.ceil(b.count / o.bundle)
        if o.avail > 0 then b.purchases = math.min(b.purchases, o.avail) end
        b.items = b.purchases * o.bundle
        b.cost = b.purchases * o.price
        plan.total = plan.total + b.cost
        if b.items <= 0 then plan.buys[vid] = nil end
    end
    return plan
end

local function DescribePlan(plan)
    for _, c in ipairs(plan.crafts) do
        local _, link = ItemInfo(c.out)
        local buff = next(c.stats or {}) and (" (" .. StatText(c.stats) .. (c.bonus < 0 and ", off-spec" or "") .. ")") or ""
        print(("  %s x%d%s"):format(link or c.name, c.crafts, buff))
    end
    for vid, b in pairs(plan.buys) do
        local _, link = ItemInfo(vid)
        print(("  buy %d %s for %s"):format(b.items, link or b.offer.name or vid, Money(b.cost)))
    end
end

------------------------------------------------------------------------
-- Buying, one purchase at a time
------------------------------------------------------------------------
local queue, waiting, merchantOpen

local function StopBuying(msg)
    queue, waiting = nil, nil
    if msg then Print(msg) end
end

local BuyNext
BuyNext = function()
    if not queue or waiting then return end
    if not merchantOpen then return StopBuying("vendor closed, stopped buying.") end
    local job = queue[1]
    if not job then
        StopBuying()
        Print("done shopping. Open your Cooking window to cook.")
        return
    end
    if job.left <= 0 then table.remove(queue, 1); return BuyNext() end

    local o = job.offer
    if safe(GetMerchantItemID(o.index)) ~= job.id then return StopBuying("vendor list changed, stopped buying.") end
    local amount = math.min(job.left, o.chunk)
    amount = math.max(o.bundle, math.floor(amount / o.bundle) * o.bundle)
    if o.price > 0 and GetMoney() < (amount / o.bundle) * o.price then
        return StopBuying("ran out of gold.")
    end
    waiting = { id = job.id, before = BagCount(job.id), amount = amount }
    local token = waiting
    BuyMerchantItem(o.index, amount)
    job.left = job.left - amount
    C_Timer.After(4, function()
        if waiting == token then StopBuying("a purchase didn't arrive (bags full?), stopped buying.") end
    end)
end

local function CheckDelivery()
    if not waiting then return end
    if BagCount(waiting.id) - waiting.before >= waiting.amount then
        waiting = nil
        C_Timer.After(0.15, BuyNext)
    end
end

local function StartBuying(plan)
    queue = {}
    for vid, b in pairs(plan.buys) do
        queue[#queue + 1] = { id = vid, offer = b.offer, left = b.items }
    end
    if #queue == 0 then queue = nil; return end
    Print(("buying ingredients for %s."):format(Money(plan.total)))
    BuyNext()
end

StaticPopupDialogs["AUTOCHEF_CONFIRM"] = {
    text = "AutoChef wants to spend %s on cooking ingredients.\n(See chat for the list.)",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, plan) StartBuying(plan) end,
    timeout = 0, whileDead = false, hideOnEscape = true, preferredIndex = 3,
}

local function Run(dry)
    if not char.recipes or not next(char.recipes) then
        if dry then Print("open your Cooking window once so I can learn your recipes.") end
        return
    end
    local plan = BuildPlan(VendorTable())
    if not next(plan.buys) then
        if dry then
            Print(#plan.crafts > 0 and "you already have everything; nothing to buy." or
                  "this vendor doesn't sell anything your bag ingredients need.")
            DescribePlan(plan)
        end
        return
    end
    Print((dry and "would buy" or "plan") .. " (" .. Money(plan.total) .. "):")
    DescribePlan(plan)
    if dry then return end
    if plan.total > GetMoney() then
        Print("not enough gold for all of it; buying what I can.")
    end
    if plan.total > db.confirmOver then
        StaticPopup_Show("AUTOCHEF_CONFIRM", Money(plan.total), nil, plan)
    else
        StartBuying(plan)
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local captureQueued
local function QueueCapture()
    if captureQueued then return end
    captureQueued = true
    C_Timer.After(0.5, function() captureQueued = false; Capture() end)
end

local function Reg(e) pcall(f.RegisterEvent, f, e) end
for _, e in ipairs({ "ADDON_LOADED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
    "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED", "MERCHANT_SHOW",
    "MERCHANT_CLOSED", "BAG_UPDATE_DELAYED", "UI_ERROR_MESSAGE" }) do Reg(e) end

f:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        AutoChefDB = AutoChefDB or {}
        db = AutoChefDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil and v ~= nil then db[k] = (type(v) == "table") and {} or v end
        end
        local key = CharKey()
        db.chars[key] = db.chars[key] or {}
        char = db.chars[key]
        return
    end
    if not db then return end

    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE"
        or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" or event == "NEW_RECIPE_LEARNED" then
        QueueCapture()
    elseif event == "MERCHANT_SHOW" then
        merchantOpen = true
        if db.enabled then
            -- give the vendor list and item data a moment to load
            for _, r in pairs(char.recipes or {}) do RequestItem(r.out) end
            C_Timer.After(0.6, function() if merchantOpen and not queue then Run(false) end end)
        end
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
        if queue then StopBuying() end
    elseif event == "BAG_UPDATE_DELAYED" then
        CheckDelivery()
    elseif event == "UI_ERROR_MESSAGE" then
        if waiting then
            local msg = arg2 or arg1
            if type(msg) == "string" and (msg == ERR_INV_FULL or msg == ERR_NOT_ENOUGH_MONEY
                or msg == ERR_ITEM_MAX_COUNT) then
                StopBuying("stopped buying: " .. msg)
            end
        end
    end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local STAT_ALIASES = { strength = "str", agility = "agi", intellect = "int", stamina = "sta",
    spirit = "spi", attackpower = "ap", spellpower = "sp", spelldamage = "sp", healing = "heal",
    mana = "mp5", health = "hp5", crit = "crit", hit = "hit" }

local function Help()
    Print("commands:")
    print("  /chef            - turn auto-buying on or off")
    print("  /chef plan       - at a vendor: show what it would buy, without buying")
    print("  /chef buy        - at a vendor: run it now")
    print("  /chef recipes    - your best recipes for your current spec")
    print("  /chef spec       - show the stat priority it's using")
    print("  /chef stats str sta - set your own stat priority (/chef stats auto to undo)")
    print("  /chef confirm 10 - ask before spending more than 10g (now " .. Money(db.confirmOver) .. ")")
    print("  /chef max 20     - cap crafts per recipe (0 = no cap, now " .. db.maxCrafts .. ")")
end

SLASH_AUTOCHEF1 = "/chef"
SLASH_AUTOCHEF2 = "/autochef"
SlashCmdList.AUTOCHEF = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        db.enabled = not db.enabled
        Print(db.enabled and "|cff00ff00on|r" or "|cffff4040off|r")
    elseif cmd == "on" or cmd == "off" then
        db.enabled = (cmd == "on")
        Print(db.enabled and "|cff00ff00on|r" or "|cffff4040off|r")
    elseif cmd == "plan" or cmd == "buy" then
        if not merchantOpen then Print("talk to a vendor first."); return end
        Run(cmd == "plan")
    elseif cmd == "recipes" then
        if not char.recipes then Print("open your Cooking window once first."); return end
        local list, myLevel = {}, UnitLevel("player") or 1
        for _, r in pairs(char.recipes) do
            local score, req, stats, bonus = ScoreRecipe(r, myLevel)
            if score then list[#list + 1] = { r = r, score = score, req = req, stats = stats, bonus = bonus } end
        end
        table.sort(list, function(a, b) return a.score > b.score end)
        Print(("%d recipes remembered; best for you:"):format(char.count or 0))
        for i = 1, math.min(8, #list) do
            local c = list[i]
            local _, link = ItemInfo(c.r.out)
            local buff = next(c.stats) and (" - " .. StatText(c.stats) .. (c.bonus < 0 and " (off-spec)" or "")) or ""
            print(("  %s, level %d%s"):format(link or c.r.name, c.req, buff))
        end
    elseif cmd == "spec" then
        local prio, src = MyPriorities()
        local names = {}
        for _, k in ipairs(prio) do names[#names + 1] = STAT_NAMES[k] or k end
        Print(("%s: %s"):format(src, table.concat(names, " > ")))
    elseif cmd == "stats" then
        if rest == "" or rest:lower() == "auto" then
            db.stats = nil; Print("using your class and spec again.")
            return
        end
        local list = {}
        for word in rest:lower():gmatch("[%a]+") do
            local k = STAT_ALIASES[word] or (STAT_NAMES[word] and word)
            if k then list[#list + 1] = k end
        end
        if #list == 0 then Print("try: /chef stats agi sta ap"); return end
        db.stats = list
        SlashCmdList.AUTOCHEF("spec")
    elseif cmd == "confirm" then
        local g = tonumber(rest)
        if not g then Print("usage: /chef confirm 10  (gold)"); return end
        db.confirmOver = math.floor(g * 10000)
        Print("will ask before spending more than " .. Money(db.confirmOver))
    elseif cmd == "max" then
        local n = tonumber(rest)
        if not n then Print("usage: /chef max 20"); return end
        db.maxCrafts = math.max(0, math.floor(n))
        Print(db.maxCrafts == 0 and "no cap on crafts" or ("up to " .. db.maxCrafts .. " crafts per recipe"))
    else
        Help()
    end
end
