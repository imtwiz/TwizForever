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
    return ns.db
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
function ns.InvalidateRecipes() cache = nil end

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
                    if p and (C_Item.GetItemCount(itemID, true) or 0) == 0 then
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
-- Buying: click = price lookup, click again = confirm (the game needs both)
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
        ns.Print(("Careful: %s is %s right now, over 1.5x its usual %s. Click again to buy anyway."):format(
            Name(b.itemID), ns.Money(price), ns.Money(ref)))
    end
    ns.UI.Refresh()
end

local function Quote(r, all, retried)
    if not ns.ahOpen then ns.Print("Open the Auction House first."); StopRun(false); return end
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
    -- gold didn't move, so nothing was bought: forget that listing and look again
    local l = live[b.itemID]
    if l then
        for i, row in ipairs(l.rows) do if row.auctionID == b.auctionID then table.remove(l.rows, i); break end end
    end
    live[b.itemID] = nil
    ns.recipeBuy = nil
    if not b.retried then
        return Quote(b.r, b.all, true)
    end
    skipped[b.itemID] = true
    Done(Name(b.itemID) .. " wouldn't go through - skipped.")
end

local function Confirm(b)
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

-- one row: first click looks up the price, second click buys it
function ns.BuyRecipe(r)
    local b = ns.recipeBuy
    if b and b.itemID == r.itemID and b.stage == "ready" then return Confirm(b) end
    if b and b.stage ~= "ready" then return end
    if not r.learnable then
        ns.Print(("You need %s %d to learn %s (you have %d)."):format(r.prof, r.level, Name(r.itemID), r.skill))
    end
    Quote(r, false)
end

Continue = function()
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
    Quote(plan[1], true)
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
    if ns.recipeRun then return Continue() end
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
    Continue()
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
    if b and b.stage == "quote" then return "Finding price..." end
    if b and b.stage == "buying" then return "Buying..." end
    if b and b.stage == "ready" then
        return ("%sConfirm %s|r"):format(b.expensive and "|cffff6060" or "", ns.Money(b.price))
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
                c[5]:SetText(b.stage == "ready" and ("|cfff0c45cConfirm|r") or "|cff808080...|r")
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
            GameTooltip:AddLine(r.learnable and "Click to look up the price, click again to buy it."
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
                  GameTooltip:AddLine("The game needs two clicks per recipe: one looks up the price, one confirms.", 0.7, 0.7, 0.7, true)
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
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "MAIL_SHOW", "MAIL_CLOSED", "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED", "NEW_RECIPE_LEARNED", "SKILL_LINES_CHANGED", "PLAYER_ENTERING_WORLD", "GET_ITEM_INFO_RECEIVED" }) do
    pcall(lev.RegisterEvent, lev, e)
end
local pendingLearn
lev:SetScript("OnEvent", function(_, event)
    if event == "NEW_RECIPE_LEARNED" or event == "SKILL_LINES_CHANGED" then wipe(infoCache) end
    if pendingLearn then return end
    pendingLearn = true
    C_Timer.After(0.4, function()
        pendingLearn = false
        if ns.S then pcall(ns.UpdateLearnButton) end
    end)
end)
