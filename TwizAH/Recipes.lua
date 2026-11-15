-- TwizAH: Recipes - the cheapest recipes you're missing for your professions.
-- Uses prices from full scans. Buy one (click its row) or Buy All, which works
-- cheapest-first and never goes past the most you said you'd spend on recipes.
-- The game needs a click to look up the price and a click to confirm each buy.
local ADDON, ns = ...

local RECIPE_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
local PRICE_GUARD = 1.5

local function DB()
    ns.db.recipeSpent = ns.db.recipeSpent or 0
    ns.db.recipeBought = ns.db.recipeBought or {}
    ns.db.recipeMail = ns.db.recipeMail or {}
    return ns.db
end

-- Recipes in your mailbox (read whenever the mailbox is open)
local function ScanMail()
    if not GetInboxNumItems then return end
    local db = DB()
    wipe(db.recipeMail)
    for i = 1, (GetInboxNumItems() or 0) do
        for a = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
            local link = GetInboxItemLink and GetInboxItemLink(i, a)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id then
                local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
                if classID == RECIPE_CLASS then db.recipeMail[id] = (db.recipeMail[id] or 0) + 1 end
            end
        end
    end
end

-- Do you already have this recipe (or one with the same name) - bought, in bags/bank, in the mailbox?
local ownedNames, ownedAt = {}, -10
local function OwnedNames()
    if GetTime() - ownedAt < 2 then return ownedNames end
    wipe(ownedNames)
    local db = DB()
    local function add(id) local n = C_Item.GetItemInfo(id); if n then ownedNames[n] = true end end
    for id in pairs(db.recipeBought) do add(id) end
    for id in pairs(db.recipeMail) do add(id) end
    for bag = 0, 4 do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id then
                local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
                if classID == RECIPE_CLASS then add(id) end
            end
        end
    end
    ownedAt = GetTime()
    return ownedNames
end

local function AlreadyHave(itemID)
    local db = DB()
    if db.recipeBought[itemID] or (db.recipeMail[itemID] or 0) > 0 then return true end
    if (C_Item.GetItemCount(itemID, true) or 0) > 0 then return true end
    if TwizCraft and TwizCraft.MailCount then
        local ok, n = pcall(TwizCraft.MailCount, itemID)
        if ok and (n or 0) > 0 then return true end
    end
    local name = C_Item.GetItemInfo(itemID)
    return name and OwnedNames()[name] or false
end

local function Strip(t)
    if type(t) ~= "string" then return nil end
    return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- "Requires %s (%d)" -> a pattern that captures the profession and level
local REQ_PATTERN
local function ReqPattern()
    if REQ_PATTERN then return REQ_PATTERN end
    local f = ITEM_MIN_SKILL or "Requires %s (%d)"
    f = f:gsub("%%%d?%$?", "%%"):gsub("([%(%)%.%-%+%[%]%^%$%?%*])", "%%%1")
    f = f:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    REQ_PATTERN = "^" .. f
    return REQ_PATTERN
end

-- What a recipe's tooltip says: known already? which profession and skill it needs?
local infoCache = {}
local function RecipeInfo(itemID)
    local c = infoCache[itemID]
    if c then return c end
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then
        c = { ok = true }; infoCache[itemID] = c; return c
    end
    local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
    if not ok or not data or not data.lines or #data.lines == 0 then
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        return nil
    end
    c = { ok = true }
    local known = ITEM_SPELL_KNOWN or "Already known"
    for _, line in ipairs(data.lines) do
        if TooltipUtil and TooltipUtil.SurfaceArgs and not line.leftText then pcall(TooltipUtil.SurfaceArgs, line) end
        local t = Strip(line.leftText)
        if t then
            if t == known or t:find(known, 1, true) then c.known = true end
            local prof, lvl = t:match(ReqPattern())
            if prof and lvl and not c.prof then c.prof, c.level = prof, tonumber(lvl) end
        end
    end
    infoCache[itemID] = c
    return c
end

local function MyProfessions()
    local out = {}
    if not (GetProfessions and GetProfessionInfo) then return out end
    local list = { GetProfessions() }
    for i = 1, 6 do
        local idx = list[i]
        if idx then
            local name, _, rank = GetProfessionInfo(idx)
            if name then out[name:lower()] = { name = name, skill = rank or 0 } end
        end
    end
    return out
end

-- Recipes TwizCraft has seen as learned (recipe item -> learned)
local function LearnedViaTwizCraft()
    local learned = {}
    local ok, c = false, nil
    if TwizCraft and TwizCraft.Char then ok, c = pcall(TwizCraft.Char) end
    if not ok then c = nil end
    for _, p in pairs(c and c.profs or {}) do
        for _, r in pairs(p.recipes or {}) do
            if r.recipeItem and r.learned then learned[r.recipeItem] = true end
        end
    end
    return learned
end

-- Live AH listings per recipe from "Refresh prices" and purchase lookups:
-- live[itemID] = { rows = { {unit, auctionID}, ... cheapest first }, t = GetTime(), commodity = bool }
-- Fresh rows let a purchase go straight to "confirm" without waiting for a search.
local live = {}
local LIVE_FRESH = 150 -- seconds
local function Live(itemID)
    local l = live[itemID]
    if l and GetTime() - l.t < LIVE_FRESH then return l end
end
local function StoreLive(itemID, rows)
    if rows == nil then return end
    local l = { rows = {}, t = GetTime() }
    if rows[1] and rows[1].commodity then
        l.commodity = true
        for _, r in ipairs(rows) do if not r.own then l.rows[1] = { unit = r.unit }; break end end
    else
        for _, r in ipairs(rows) do
            if not r.own and (r.qty or 1) == 1 and r.auctionID then l.rows[#l.rows + 1] = { unit = r.unit, auctionID = r.auctionID } end
        end
    end
    live[itemID] = l
end

local cache, cacheAt = nil, -10
function ns.InvalidateRecipes() cache = nil; ownedAt = -10 end

-- { { itemID, price, prof, level, learnable, need }, ... } learnable first, cheapest first
function ns.RecipeList()
    if cache and GetTime() - cacheAt < 2 then return cache end
    local db = DB()
    local profs = MyProfessions()
    local viaTC = LearnedViaTwizCraft()
    local list, waiting = {}, 0
    for itemID, m in pairs(ns.db.market or {}) do
        if type(itemID) == "number" and type(m) == "table" and m.min then
            local _, _, subType, _, icon, classID, subID = C_Item.GetItemInfoInstant(itemID)
            if classID == RECIPE_CLASS and subID ~= 0 and not db.recipeBought[itemID] and not viaTC[itemID] then
                local info = RecipeInfo(itemID)
                if not info then
                    waiting = waiting + 1
                elseif not info.known then
                    local profName = (info.prof or subType or ""):lower()
                    local p = profs[profName]
                    if p and not AlreadyHave(itemID) then
                        local price = ns.KnownPrice(itemID) or m.min
                        local l = Live(itemID)
                        if l then price = l.rows[1] and l.rows[1].unit end -- nil: sold out right now
                        local level = info.level or 0
                        if price then list[#list + 1] = { itemID = itemID, icon = icon, price = price, prof = p.name,
                            level = level, skill = p.skill, learnable = p.skill >= level, med = m.med, live = l ~= nil } end
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.learnable ~= b.learnable then return a.learnable end
        if a.price ~= b.price then return a.price < b.price end
        return a.itemID < b.itemID
    end)
    -- one per recipe name: keep the cheapest
    local seen, deduped = {}, {}
    for _, r in ipairs(list) do
        local n = C_Item.GetItemInfo(r.itemID) or r.itemID
        if not seen[n] then seen[n] = true; deduped[#deduped + 1] = r end
    end
    list = deduped
    ns.recipeWaiting = waiting
    cache, cacheAt = list, GetTime()
    return list
end

function ns.RecipeBudgetLeft()
    local db = DB()
    return math.max(0, (ns.S.recipeBudget or 0) - db.recipeSpent)
end

-- what Buy All would buy: cheapest learnable recipes that fit in what's left of the budget
local skipped = {}
function ns.RecipePlan()
    local left, total, plan = ns.RecipeBudgetLeft(), 0, {}
    for _, r in ipairs(ns.RecipeList()) do
        if r.learnable and not skipped[r.itemID] and total + r.price <= left then
            plan[#plan + 1] = r
            total = total + r.price
        end
    end
    return plan, total
end

------------------------------------------------------------------------
-- Buying: one click / wheel notch / key press per purchase (the game needs one each)
------------------------------------------------------------------------
ns.recipeBuy = nil -- { itemID, stage = "quote" | "ready" | "buying", price, auctionID, commodity, all, expensive }

local function Name(id) return C_Item.GetItemInfo(id) or ("item " .. id) end

-- Buy All run: once started, prices are looked up automatically and each
-- click / wheel notch / key press buys one recipe. Gone or pricier-than-usual
-- recipes are skipped and the run moves on by itself.
ns.recipeRun = nil -- { n, spent }
local Continue

local function StopRun(msg)
    local run = ns.recipeRun
    ns.recipeRun = nil
    if run and msg ~= false then
        ns.Print(msg or ("Buy All finished: %d recipe%s for %s."):format(run.n, run.n == 1 and "" or "s", ns.Money(run.spent)))
    end
    if ns.UpdateWheelPost then ns.UpdateWheelPost() end
    if ns.UpdateLearnButton then pcall(ns.UpdateLearnButton) end
end
ns.StopRecipeRun = StopRun

local function Done(msg, stop)
    if msg then ns.Print(msg) end
    ns.recipeBuy = nil
    ns.InvalidateRecipes()
    if stop and ns.recipeRun then StopRun() end
    if ns.recipeRun then C_Timer.After(0, function() if ns.recipeRun and not ns.recipeBuy then Continue() end end) end
    ns.UI.Refresh()
end

local function Bought(b)
    local db = DB()
    db.recipeSpent = db.recipeSpent + (b.price or 0)
    db.recipeBought[b.itemID] = true
    if TwizCraft and TwizCraft.NoteMailed then pcall(TwizCraft.NoteMailed, b.itemID, 1) end
    local l = live[b.itemID]
    if l and l.rows[1] and l.rows[1].auctionID == b.auctionID then table.remove(l.rows, 1) end
    if ns.recipeRun and b.all then ns.recipeRun.n = ns.recipeRun.n + 1; ns.recipeRun.spent = ns.recipeRun.spent + (b.price or 0) end
    Done(("Bought %s for %s (recipes spent: %s of %s). It's in your mailbox - learn it from your bags."):format(
        Name(b.itemID), ns.Money(b.price or 0), ns.Money(db.recipeSpent), ns.Money(ns.S.recipeBudget or 0)))
end

local function Ready(b, price, auctionID)
    b.price, b.auctionID, b.stage = price, auctionID, "ready"
    local ref = b.med or ns.KnownPrice(b.itemID)
    b.expensive = ref and price > ref * PRICE_GUARD
    if b.all and price > ns.RecipeBudgetLeft() then
        skipped[b.itemID] = true
        return Done(("%s costs %s now - more than is left of your recipe budget. Skipped."):format(Name(b.itemID), ns.Money(price)))
    end
    if b.expensive then
        if b.all then
            skipped[b.itemID] = true
            return Done(("%s is %s right now, over 1.5x its usual %s. Skipped (click its row to buy it anyway)."):format(
                Name(b.itemID), ns.Money(price), ns.Money(ref)))
        end
    end
    ns.UI.Refresh()
end

local Confirm
-- buyNow: this came from your click/key/wheel, so if the price is already known, buy right away
local function Quote(r, all, retried, buyNow)
    if not ns.ahOpen then ns.Print("Open the Auction House first."); StopRun(false); return end
    if AlreadyHave(r.itemID) then
        ns.InvalidateRecipes()
        if all then skipped[r.itemID] = true; return Done() end
        return ns.Print("You already have " .. Name(r.itemID) .. " - not buying another.")
    end
    -- recipes are normally single items; trust the item key when the game knows
    local okK, keyInfo = pcall(C_AuctionHouse.GetItemKeyInfo, C_AuctionHouse.MakeItemKey(r.itemID))
    local commodity = okK and type(keyInfo) == "table" and keyInfo.isCommodity == true
    local b = { itemID = r.itemID, r = r, retried = retried, stage = "quote", commodity = commodity, all = all, med = r.med, at = GetTime() }
    ns.recipeBuy = b
    local function StartCommodity()
        b.commodity = true
        C_AuctionHouse.StartCommoditiesPurchase(r.itemID, 1)
    end
    local l = Live(r.itemID)
    if l and l.commodity then commodity = true end
    if commodity then
        StartCommodity()
    elseif l and l.rows[1] then
        -- prices were refreshed a moment ago: ready to buy straight away, and
        -- search it again right now so the AH has this listing fresh when you confirm
        b.fromLive = true
        Ready(b, l.rows[1].unit, l.rows[1].auctionID)
        if ns.recipeBuy ~= b then return end
        if buyNow and b.stage == "ready" then return Confirm(b) end
        b.fresh = function(rows)
            StoreLive(r.itemID, rows)
            if ns.recipeBuy ~= b or b.stage ~= "ready" or rows == nil then return end
            local nl = live[r.itemID]
            local row = nl and not nl.commodity and nl.rows[1]
            if not row then
                skipped[r.itemID] = true
                return Done(Name(r.itemID) .. " isn't on the AH any more. Skipped.")
            end
            if row.auctionID ~= b.auctionID or row.unit ~= b.price then Ready(b, row.unit, row.auctionID) end
        end
        ns.QueueLookup(r.itemID, nil, false, b.fresh, true)
        return
    else
        b.lookup = function(rows)
            if ns.recipeBuy ~= b then return end
            if rows == nil then
                -- the AH didn't answer in time; try once more before giving up on it
                ns.recipeBuy = nil
                if not retried then return Quote(r, all, true) end
                skipped[r.itemID] = true
                return Done("The AH didn't answer about " .. Name(r.itemID) .. " - skipped.")
            end
            StoreLive(r.itemID, rows)
            if rows[1] and rows[1].commodity then return StartCommodity() end -- the game sells it as a commodity
            for _, row in ipairs(rows) do
                if not row.own and (row.qty or 1) == 1 and row.auctionID then return Ready(b, row.unit, row.auctionID) end
            end
            skipped[r.itemID] = true
            Done(Name(r.itemID) .. " isn't on the AH any more. Skipped.")
        end
        ns.QueueLookup(r.itemID, nil, false, b.lookup, true)
    end
    C_Timer.After(15, function()
        if ns.recipeBuy == b and b.stage == "quote" then
            if b.lookup and ns.DropLookup then ns.DropLookup(b.lookup) end
            if b.commodity then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
            ns.recipeBuy = nil
            if not retried then return Quote(r, all, true) end
            skipped[r.itemID] = true
            Done("No price came back for " .. Name(r.itemID) .. " - skipped.")
        end
    end)
    ns.UI.Refresh()
end

-- The purchase went through when your gold drops by the price (the AH's own
-- "purchase complete" signals aren't reliable on every client).
local function PaidFor(b)
    return b.moneyBefore and GetMoney() <= b.moneyBefore - math.floor(b.price * 0.9)
end

local function NotThrough(b)
    -- No gold change yet. Don't risk buying it twice: look at the AH again. If the very
    -- same listing is still there, nothing went through and the next press retries that
    -- one listing (it can't be bought twice). If it's gone, assume it may be yours.
    b.stage = "checking"
    ns.QueueLookup(b.itemID, nil, false, function(rows)
        if ns.recipeBuy ~= b then return end
        if PaidFor(b) then return Bought(b) end
        StoreLive(b.itemID, rows)
        local still = false
        for _, row in ipairs(rows or {}) do if row.auctionID == b.auctionID then still = true end end
        if still and not b.retried then
            b.retried = true
            b.stage = "ready"
            ns.Print(Name(b.itemID) .. " didn't go through yet - press again to retry that same listing.")
            return ns.UI.Refresh()
        end
        -- unsure: treat it as bought so it's never bought twice, and count the gold against the budget
        local db = DB()
        db.recipeBought[b.itemID] = true
        db.recipeSpent = db.recipeSpent + (b.price or 0)
        if ns.recipeRun and b.all then ns.recipeRun.n = ns.recipeRun.n + 1; ns.recipeRun.spent = ns.recipeRun.spent + (b.price or 0) end
        Done(("Couldn't confirm %s went through - skipping it so you don't buy it twice. Check your mailbox."):format(Name(b.itemID)))
    end, true)
    ns.UI.Refresh()
end

Confirm = function(b)
    if b.price > GetMoney() then return Done("Not enough gold for " .. Name(b.itemID) .. ".", true) end
    b.stage, b.at, b.moneyBefore = "buying", GetTime(), GetMoney()
    if b.commodity then
        C_AuctionHouse.ConfirmCommoditiesPurchase(b.itemID, 1)
    else
        C_AuctionHouse.PlaceBid(b.auctionID, b.price)
    end
    C_Timer.After(5, function()
        if ns.recipeBuy == b and b.stage == "buying" then
            if PaidFor(b) then return Bought(b) end
            NotThrough(b)
        end
    end)
    ns.UI.Refresh()
end

-- one row click buys it (if its price is still being looked up, the next click does)
function ns.BuyRecipe(r)
    local b = ns.recipeBuy
    if b and b.itemID == r.itemID and b.stage == "ready" then return Confirm(b) end
    if b and b.stage ~= "ready" then return end
    if not r.learnable then
        ns.Print(("You need %s %d to learn %s (you have %d)."):format(r.prof, r.level, Name(r.itemID), r.skill))
    end
    Quote(r, false, false, true)
end

Continue = function(buyNow)
    local plan = ns.RecipePlan()
    if not plan[1] then
        local more = 0
        for _, r in ipairs(ns.RecipeList()) do if r.learnable and not skipped[r.itemID] then more = more + 1 end end
        if more > 0 then
            return StopRun(("Buy All finished: %d recipe%s for %s. %d more cost more than the %s left of your max spend - raise it to keep going."):format(
                ns.recipeRun.n, ns.recipeRun.n == 1 and "" or "s", ns.Money(ns.recipeRun.spent), more, ns.Money(ns.RecipeBudgetLeft())))
        end
        return StopRun()
    end
    Quote(plan[1], true, false, buyNow)
end

local watchdog = CreateFrame("Frame")
local idleSince
watchdog:SetScript("OnUpdate", function()
    if not ns.recipeRun or ns.recipeBuy then idleSince = nil; return end
    idleSince = idleSince or GetTime()
    if GetTime() - idleSince > 0.5 then idleSince = nil; Continue() end
end)

-- each press: buys the recipe whose price is ready, or starts the run
function ns.BuyAllRecipes()
    local b = ns.recipeBuy
    if b and b.stage == "ready" then return Confirm(b) end
    if b then return end
    if ns.recipeRun then return Continue(true) end
    local plan = ns.RecipePlan()
    if not plan[1] then
        if (ns.S.recipeBudget or 0) <= 0 then ns.Print("Set a max spend first (the box next to Buy All, or /dw recipemax 10g).")
        else ns.Print("Nothing else fits in your recipe budget.") end
        return
    end
    ns.recipeRun = { n = 0, spent = 0 }
    if ns.UpdateWheelPost then ns.UpdateWheelPost() end
    if ns.S.wheelPost then
        ns.Print("Buying recipes: each click, mouse-wheel notch or key press buys the next one (the game needs one per purchase). Cancel to stop.")
    end
    Continue(true)
end

function ns.CancelRecipeBuy()
    local b = ns.recipeBuy
    if b and b.commodity then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
    StopRun("Buy All stopped.")
    Done()
end

function ns.SetRecipeBudget(copper)
    ns.S.recipeBudget = math.max(0, copper or 0)
    ns.InvalidateRecipes()
    ns.Print(("Max spend on recipes: %s (spent so far %s)."):format(ns.Money(ns.S.recipeBudget), ns.Money(DB().recipeSpent)))
    ns.UI.Refresh()
end

function ns.ResetRecipeSpent()
    DB().recipeSpent = 0
    ns.Print("Recipe spending reset to 0.")
    ns.UI.Refresh()
end

------------------------------------------------------------------------
-- Refresh prices: look every recipe on the list up on the AH (no clicks needed)
------------------------------------------------------------------------
local refreshing, refreshTotal = 0, 0
function ns.RefreshRecipePrices(quiet)
    if not ns.ahOpen then if not quiet then ns.Print("Open the Auction House first.") end return end
    if refreshing > 0 then return end
    ns.InvalidateRecipes()
    local list = ns.RecipeList()
    refreshTotal = math.min(#list, 60)
    if refreshTotal == 0 then return end
    refreshing = refreshTotal
    for i = 1, refreshTotal do
        local id = list[i].itemID
        ns.QueueLookup(id, nil, false, function(rows)
            StoreLive(id, rows)
            refreshing = math.max(0, refreshing - 1)
            if refreshing == 0 then
                ns.InvalidateRecipes()
                if not quiet then ns.Print(("Recipe prices refreshed (%d looked up)."):format(refreshTotal)) end
            end
            ns.UI.Refresh()
        end)
    end
    ns.UI.Refresh()
end

local autoTicker
local function StartAutoRefresh()
    if autoTicker then autoTicker:Cancel() end
    C_Timer.After(5, function() ns.RefreshRecipePrices(true) end)
    autoTicker = C_Timer.NewTicker(120, function()
        if ns.ahOpen and not ns.scanning then ns.RefreshRecipePrices(true) end
    end)
end

local function BuyAllText()
    local b = ns.recipeBuy
    if b and (b.stage == "quote" or b.stage == "checking") then return "Finding price..." end
    if b and b.stage == "buying" then return "Buying..." end
    if b and b.stage == "ready" then
        return ("Buy %s - %s"):format(Name(b.itemID), ns.Money(b.price))
    end
    local plan, total = ns.RecipePlan()
    return ("Buy All (%d) - %s"):format(#plan, ns.Money(total))
end

------------------------------------------------------------------------
-- Tab
------------------------------------------------------------------------
ns.UI_RegisterLater = ns.UI_RegisterLater or {}
table.insert(ns.UI_RegisterLater, function(UI)
    UI.RegisterTab("RECIPES", {
        cols = {
            { title = "Recipe",     w = 250, j = "LEFT" },
            { title = "Profession", w = 100, j = "LEFT" },
            { title = "Skill",      w = 60,  j = "RIGHT" },
            { title = "Price",      w = 95,  j = "RIGHT" },
            { title = "",           w = 95,  j = "CENTER" },
        },
        list = function() return ns.RecipeList() end,
        fill = function(row, r, c, ItemLabel)
            c[1]:SetText(ItemLabel(nil, nil, r.itemID))
            c[2]:SetText(r.prof)
            c[3]:SetText(r.learnable and ("|cff9aa1ab%d|r"):format(r.level) or ("|cffff8060%d|r"):format(r.level))
            c[4]:SetText(ns.Money(r.price))
            local b = ns.recipeBuy
            if b and b.itemID == r.itemID then
                c[5]:SetText(b.stage == "ready" and ("|cfff0c45cBuy|r") or "|cff808080...|r")
            else
                c[5]:SetText(r.learnable and "|cfff0c45cBuy|r" or "|cff808080Later|r")
            end
            row.sel:SetShown(b and b.itemID == r.itemID or false)
        end,
        tooltip = function(r)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Cheapest on the AH", ns.Money(r.price), 1, 1, 1)
            if r.med then GameTooltip:AddDoubleLine("Usual price", ns.Money(r.med), 1, 1, 1) end
            GameTooltip:AddDoubleLine(r.prof .. " needed", ("%d (you have %d)"):format(r.level, r.skill), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddLine(r.learnable and "Click to buy it."
                or "Too high for your skill right now - Buy All skips it.", 0.6, 0.6, 0.6, true)
        end,
        onClick = function(r) ns.BuyRecipe(r) end,
        summary = function()
            local list = ns.RecipeList()
            local learnable, cheapest = 0, nil
            for _, r in ipairs(list) do
                if r.learnable then learnable = learnable + 1; cheapest = cheapest or r.price end
            end
            local plan, total = ns.RecipePlan()
            local text
            if not next(ns.db.market or {}) then
                text = "Run a full AH scan to find recipes you're missing."
            elseif #list == 0 then
                text = "No missing recipes for your professions are on the AH right now."
            else
                text = ("%d recipes you can learn now are on the AH (cheapest %s). Buy All gets |cff8fe08f%d|r of them for |cfff0c45c%s|r."):format(
                    learnable, ns.Money(cheapest or 0), #plan, ns.Money(total))
            end
            local spent = DB().recipeSpent
            local status = ("Max spend %s  |  spent %s  |  %s left"):format(ns.Money(ns.S.recipeBudget or 0),
                ns.Money(spent), ns.Money(ns.RecipeBudgetLeft()))
            if (ns.recipeWaiting or 0) > 0 then status = status .. ("  |  reading %d tooltips..."):format(ns.recipeWaiting) end
            return text, status
        end,
        onShow = function() ns.InvalidateRecipes() end,
        buttons = {
            { text = "Buy All", width = 170, kind = "primary", onClick = function() ns.BuyAllRecipes() end,
              label = BuyAllText,
              enabled = function() return ns.ahOpen and (ns.recipeBuy ~= nil or ns.RecipePlan()[1] ~= nil) or false end,
              tooltip = function()
                  local plan, total = ns.RecipePlan()
                  GameTooltip:SetText("Buy All Recipes")
                  GameTooltip:AddLine("Buys the cheapest recipes you can learn now, one after another, until your max spend is reached.", 1, 1, 1, true)
                  GameTooltip:AddLine("Each click, mouse-wheel notch or key press buys one recipe - the game needs one per purchase. Prices are kept fresh in the background.", 0.7, 0.7, 0.7, true)
                  GameTooltip:AddLine(" ")
                  for i, r in ipairs(plan) do
                      if i > 12 then GameTooltip:AddLine(("...and %d more"):format(#plan - 12), 0.7, 0.7, 0.7); break end
                      GameTooltip:AddDoubleLine(Name(r.itemID), ns.Money(r.price), 1, 1, 1, 1, 1, 1)
                  end
                  GameTooltip:AddDoubleLine("Total", ns.Money(total), 1, 0.82, 0, 1, 0.82, 0)
              end },
            { text = "Refresh prices", width = 110, onClick = function() ns.RefreshRecipePrices() end,
              label = function()
                  return refreshing > 0 and ("Refreshing %d/%d"):format(refreshTotal - refreshing, refreshTotal) or "Refresh prices"
              end,
              enabled = function() return ns.ahOpen and refreshing == 0 or false end,
              tooltip = function()
                  GameTooltip:SetText("Refresh prices")
                  GameTooltip:AddLine("Looks up every recipe on this list on the AH right now: drops ones that sold, updates prices, and lets Buy All buy without waiting for a search. Runs by itself every 2 minutes while the AH is open.", 1, 1, 1, true)
              end },
            { text = "Cancel", width = 64, onClick = function() ns.CancelRecipeBuy() end,
              enabled = function() return ns.recipeBuy ~= nil end },
        },
        -- the max-spend box sits after the buttons
        build = function(frame, after)
            local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetText("Max spend")
            label:SetTextColor(unpack(ns.Skin.C.muted))
            label:SetPoint("LEFT", after, "RIGHT", 12, 0)
            local box = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
            ns.Skin.Card(box)
            box:SetSize(70, 24)
            box:SetPoint("LEFT", label, "RIGHT", 6, 0)
            box:SetAutoFocus(false)
            box:SetFontObject("GameFontHighlightSmall")
            box:SetTextInsets(6, 6, 0, 0)
            local function Show()
                local c = ns.S.recipeBudget or 0
                local g, sv = math.floor(c / 10000), math.floor(c % 10000 / 100)
                box:SetText(sv > 0 and ("%dg%ds"):format(g, sv) or ("%dg"):format(g))
            end
            local function Apply(self)
                local t = (self:GetText() or ""):gsub("%s", "")
                local v = t:match("^%d+$") and tonumber(t) * 10000 or ns.ParseMoney(t)
                if v then ns.SetRecipeBudget(v) else ns.Print("Type gold like 10, 10g or 2g50s.") end
                self:ClearFocus()
            end
            box:SetScript("OnEnterPressed", Apply)
            box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Show() end)
            box:SetScript("OnEditFocusLost", function() Show() end)
            box:SetScript("OnShow", Show)
            Show()
            ns.Skin.Tip(box, "Max spend on recipes", "The most Buy All will spend on recipes in total. Type gold (10, 10g, 2g50s) and press Enter. /dw recipemax reset clears what's been spent.")
            ns.recipeBox = box
            return { label, box }
        end,
    })
end)

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
    "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR",
    "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_SHOW", "CHAT_MSG_SYSTEM", "PLAYER_MONEY", "NEW_RECIPE_LEARNED", "SKILL_LINES_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1, a2)
    local b = ns.recipeBuy
    if event == "COMMODITY_PRICE_UPDATED" then
        if b and b.commodity and b.stage == "quote" then Ready(b, a2 or a1) end
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
        if b and b.commodity and b.stage == "quote" then skipped[b.itemID] = true; Done(Name(b.itemID) .. " isn't on the AH any more. Skipped.") end
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        if b and b.commodity and b.stage == "buying" then Bought(b) end
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        if b and b.commodity and b.stage == "buying" then skipped[b.itemID] = true; Done("Purchase failed for " .. Name(b.itemID) .. " - skipped.") end
    elseif event == "PLAYER_MONEY" then
        if b and b.stage == "buying" and PaidFor(b) then Bought(b) end
    elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
        if b and not b.commodity and b.stage == "buying" and (not a1 or a1 == b.auctionID) then Bought(b) end
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
        if b and not b.commodity and b.stage == "buying" then
            -- that listing is gone: try the next one we already know about, then a fresh search
            local l = live[b.itemID]
            if l then
                for i, row in ipairs(l.rows) do if row.auctionID == b.auctionID then table.remove(l.rows, i); break end end
                if l.rows[1] and GetTime() - l.t < LIVE_FRESH then
                    b.stage = "quote"
                    return Ready(b, l.rows[1].unit, l.rows[1].auctionID)
                end
                live[b.itemID] = nil
            end
            if not b.retried then
                ns.Print(Name(b.itemID) .. " was just sold to someone else - looking for another listing.")
                ns.recipeBuy = nil
                return Quote(b.r, b.all, true)
            end
            skipped[b.itemID] = true
            Done("The AH said no to " .. Name(b.itemID) .. " again. Skipped.")
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        -- "You won an auction for X"
        if b and not b.commodity and b.stage == "buying" and ERR_AUCTION_WON_S and type(a1) == "string" then
            local name = C_Item.GetItemInfo(b.itemID)
            if name and a1 == ERR_AUCTION_WON_S:format(name) then Bought(b) end
        end
    elseif event == "AUCTION_HOUSE_SHOW" then
        StartAutoRefresh()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ns.recipeBuy = nil; wipe(skipped)
        if autoTicker then autoTicker:Cancel(); autoTicker = nil end
        refreshing = 0
        if ns.recipeRun then StopRun() end
    else
        ns.InvalidateRecipes(); wipe(infoCache)
    end
end)

------------------------------------------------------------------------
-- Auto-learn: recipes in your bags that you can learn now.
-- The game only lets a recipe be used from a real click or key press, so this
-- is a secure "Learn" button; at the mailbox or AH your mouse wheel presses it.
------------------------------------------------------------------------
function ns.LearnableInBags()
    local out = {}
    local profs = MyProfessions()
    for bag = 0, 4 do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id then
                local _, _, subType, _, _, classID, subID = C_Item.GetItemInfoInstant(id)
                if classID == RECIPE_CLASS and subID ~= 0 then
                    local info = RecipeInfo(id)
                    if info and not info.known then
                        local p = profs[(info.prof or subType or ""):lower()]
                        if p and p.skill >= (info.level or 0) then out[#out + 1] = { bag = bag, slot = slot, itemID = id } end
                    end
                end
            end
        end
    end
    return out
end

local learnBtn, learnOwner, learnBound
local function LearnButton()
    if learnBtn then return learnBtn end
    learnBtn = CreateFrame("Button", "TwizAHLearnButton", UIParent, "SecureActionButtonTemplate,BackdropTemplate")
    learnBtn:SetSize(190, 28)
    learnBtn:SetFrameStrata("DIALOG")
    learnBtn:SetPoint("TOP", UIParent, "TOP", 0, -120)
    learnBtn:SetMovable(true); learnBtn:SetClampedToScreen(true)
    learnBtn:RegisterForClicks("AnyUp", "AnyDown")
    learnBtn:RegisterForDrag("RightButton")
    learnBtn:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    learnBtn:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    learnBtn:SetAttribute("type", "macro")
    if ns.Skin then
        ns.Skin.Panel(learnBtn)
        learnBtn:SetBackdropColor(0.941, 0.769, 0.361, 1)
    end
    learnBtn.text = learnBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    learnBtn.text:SetPoint("CENTER")
    learnBtn.text:SetTextColor(0.102, 0.078, 0.031)
    learnBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("TwizAH: learn recipes")
        GameTooltip:AddLine("Each click (or mouse-wheel notch at the mailbox or AH) learns the next recipe in your bags. The game needs one press per recipe.", 1, 1, 1, true)
        GameTooltip:AddLine("Right-drag to move. /dw autolearn off to hide.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    learnBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    learnBtn:Hide()
    learnOwner = CreateFrame("Frame")
    return learnBtn
end

function ns.UpdateLearnButton()
    if InCombatLockdown and InCombatLockdown() then return end
    local list = (ns.S and ns.S.autoLearn ~= false) and ns.LearnableInBags() or {}
    local b = LearnButton()
    local first = list[1]
    if first then
        b:SetAttribute("macrotext", ("/use %d %d"):format(first.bag, first.slot))
        b.text:SetText(#list > 1 and ("Learn recipes (%d)"):format(#list) or "Learn recipe")
        b:Show()
    else
        b:Hide()
    end
    -- wheel learns while you're at the mailbox or AH (and no Buy All run needs it)
    local wantWheel = first and ns.S.wheelPost and not ns.recipeRun
        and ((MailFrame and MailFrame:IsShown()) or ns.ahOpen) and true or false
    ns.learnWheel = wantWheel
    if ns.UpdateWheelPost then ns.UpdateWheelPost() end -- Post All lets go of the wheel first
    if wantWheel ~= learnBound then
        if wantWheel then
            SetOverrideBindingClick(learnOwner, true, "MOUSEWHEELUP", "TwizAHLearnButton", "LeftButton")
            SetOverrideBindingClick(learnOwner, true, "MOUSEWHEELDOWN", "TwizAHLearnButton", "LeftButton")
        else
            ClearOverrideBindings(learnOwner)
        end
        learnBound = wantWheel
    end
end

local lev = CreateFrame("Frame")
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED", "NEW_RECIPE_LEARNED", "SKILL_LINES_CHANGED", "PLAYER_ENTERING_WORLD", "GET_ITEM_INFO_RECEIVED" }) do
    pcall(lev.RegisterEvent, lev, e)
end
local pendingLearn
lev:SetScript("OnEvent", function(_, event)
    if event == "NEW_RECIPE_LEARNED" or event == "SKILL_LINES_CHANGED" then wipe(infoCache) end
    if event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then pcall(ScanMail); ns.InvalidateRecipes() end
    if pendingLearn then return end
    pendingLearn = true
    C_Timer.After(0.4, function()
        pendingLearn = false
        if ns.S then pcall(ns.UpdateLearnButton) end
    end)
end)

------------------------------------------------------------------------
-- Unattended learning, the way TwizOpen opens clams: when no vendor, bank,
-- mailbox, trade or AH window is open (using an item there would sell, store
-- or attach it), you're out of combat and not casting, learn the next recipe.
-- If the game ever blocks it, the Learn button above takes over.
------------------------------------------------------------------------
local windows, learnBusy, learnTries, blockedAuto = {}, nil, {}, false
local WINDOW_OPEN = { MERCHANT_SHOW = "merchant", BANKFRAME_OPENED = "bank", MAIL_SHOW = "mail",
    TRADE_SHOW = "trade", AUCTION_HOUSE_SHOW = "ah", GUILDBANKFRAME_OPENED = "gbank" }
local WINDOW_CLOSE = { MERCHANT_CLOSED = "merchant", BANKFRAME_CLOSED = "bank", MAIL_CLOSED = "mail",
    TRADE_CLOSED = "trade", AUCTION_HOUSE_CLOSED = "ah", GUILDBANKFRAME_CLOSED = "gbank" }

local function LearnBlocked()
    if blockedAuto or not ns.S or ns.S.autoLearn == false then return true end
    if next(windows) then return true end
    if InCombatLockdown and InCombatLockdown() then return true end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return true end
    if UnitCastingInfo and UnitCastingInfo("player") then return true end
    if UnitChannelInfo and UnitChannelInfo("player") then return true end
    if GetCursorInfo and GetCursorInfo() then return true end
    return false
end

local LearnStep
local function ScheduleLearn(t) C_Timer.After(t or 1, function() LearnStep() end) end

LearnStep = function()
    if learnBusy or LearnBlocked() then return end
    for _, e in ipairs(ns.LearnableInBags()) do
        if (learnTries[e.itemID] or 0) < 2 then
            learnTries[e.itemID] = (learnTries[e.itemID] or 0) + 1
            local name = C_Item.GetItemInfo(e.itemID) or "a recipe"
            learnBusy = { itemID = e.itemID, name = name, before = C_Item.GetItemCount(e.itemID) or 0 }
            local token = learnBusy
            if C_Container and C_Container.UseContainerItem then C_Container.UseContainerItem(e.bag, e.slot)
            else UseContainerItem(e.bag, e.slot) end
            C_Timer.After(2.5, function()
                if learnBusy ~= token then return end
                learnBusy = nil
                if (C_Item.GetItemCount(token.itemID) or 0) < token.before then
                    ns.Print("Learned " .. token.name .. ".")
                    learnTries[token.itemID] = nil
                elseif learnTries[token.itemID] >= 2 then
                    ns.Print("Couldn't learn " .. token.name .. " - use the Learn button or right-click it.")
                end
                wipe(infoCache)
                pcall(ns.UpdateLearnButton)
                ScheduleLearn(0.5)
            end)
            return
        end
    end
end

local auto = CreateFrame("Frame")
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "NEW_RECIPE_LEARNED",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "MERCHANT_SHOW", "MERCHANT_CLOSED", "BANKFRAME_OPENED",
    "BANKFRAME_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "TRADE_SHOW", "TRADE_CLOSED", "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED" }) do
    pcall(auto.RegisterEvent, auto, e)
end
auto:SetScript("OnEvent", function(_, event, a1)
    if WINDOW_OPEN[event] then windows[WINDOW_OPEN[event]] = true; return end
    if WINDOW_CLOSE[event] then windows[WINDOW_CLOSE[event]] = nil; ScheduleLearn(1); return end
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if a1 == ADDON and learnBusy and not blockedAuto then
            blockedAuto = true; learnBusy = nil
            ns.Print("The game won't let addons learn recipes by themselves here - use the gold Learn button (one click each).")
        end
        return
    end
    if event == "NEW_RECIPE_LEARNED" and learnBusy then
        ns.Print("Learned " .. learnBusy.name .. ".")
        learnTries[learnBusy.itemID] = nil
        learnBusy = nil
        wipe(infoCache)
        ScheduleLearn(0.5)
        return
    end
    ScheduleLearn(1)
end)
