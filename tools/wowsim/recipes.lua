-- TwizAH: Recipes tab - cheapest missing recipes, Buy one, Buy All within a max spend
ADDON_DIR = REPO .. "/TwizAH"
dofile(REPO .. "/tools/wowsim/scenario.lua")
local ns = TwizAH
local L = function(s) SIM.log[#SIM.log + 1] = s end

GetProfessions = function() return 1, 2 end
GetProfessionInfo = function(i)
    if i == 1 then return "Tailoring", 0, 90 end
    return "Mining", 0, 60
end
SIM.tooltipLines = SIM.tooltipLines or {}
local function recipe(id, name, prof, level, sub, price, extra)
    SIM.items[id] = { name = name, vendor = 10, classID = 9, subID = sub, quality = 1 }
    SIM.tooltipLines[id] = { "Requires " .. prof .. " (" .. level .. ")" }
    if extra then SIM.tooltipLines[id][2] = extra end
    SIM.ah[id] = { commodity = false, listings = { { unit = price, qty = 1, auctionID = id * 10 }, { unit = price * 2, qty = 1, auctionID = id * 10 + 1 } } }
    ns.db.market[id] = { min = price, med = price, n = 2, q = 2, t = time() }
end
recipe(5001, "Pattern: Cheap Shirt", "Tailoring", 50, 2, 2000)
recipe(5002, "Pattern: Mid Pants", "Tailoring", 75, 2, 30000)
recipe(5003, "Pattern: Big Robe", "Tailoring", 85, 2, 90000)
recipe(5004, "Pattern: Too Hard", "Tailoring", 150, 2, 500)
recipe(5005, "Pattern: Known One", "Tailoring", 40, 2, 100, "Already known")
recipe(5006, "Recipe: Other Prof", "Alchemy", 10, 6, 100)
recipe(5007, "Pattern: Got It", "Tailoring", 20, 2, 300)
SIM.PutInBags(5007, 1)

SIM.onPlaceBid = function(auctionID, amount)
    SIM.money = SIM.money - amount
    C_Timer.After(0.4, function() SIM.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", auctionID) end)
end

AuctionHouseFrame.__shown = true; SIM.Fire("AUCTION_HOUSE_SHOW"); SIM.Advance(1)
ns.S.recipeBudget = 50000 -- 5g
ns.db.recipeSpent = 0
local f = ns.UI._frame(); f:Show(); ns.UI.SetTab("RECIPES"); SIM.Advance(1)

local names = {}
for _, r in ipairs(ns.RecipeList()) do names[#names + 1] = ("%s:%d%s"):format(SIM.items[r.itemID].name, r.price, r.learnable and "" or "(later)") end
L("list: " .. table.concat(names, ", "))
local plan, total = ns.RecipePlan()
L(("plan: %d recipes for %d"):format(#plan, total))
L("summary: " .. (f.summary:GetText() or ""))
L("status: " .. (f.status:GetText() or ""))
local def = ns.extraTabs.RECIPES
local buyAll = def.__buttons[1]
L("button: " .. (buyAll:GetText() or "") .. " shown=" .. tostring(buyAll.__shown))
L("max box: " .. tostring(ns.recipeBox and ns.recipeBox:GetText()))

-- Buy All: click, click (quote, confirm) until nothing fits
for i = 1, 12 do
    buyAll:Click(); SIM.Advance(1.2)
end
L(("spent %d, left %d, bids %d, money %d"):format(ns.db.recipeSpent, ns.RecipeBudgetLeft(), #(SIM.bids or {}), SIM.money))
local after = {}
for _, r in ipairs(ns.RecipeList()) do after[#after + 1] = SIM.items[r.itemID].name end
L("still missing: " .. table.concat(after, ", "))
L("button after: " .. (buyAll:GetText() or ""))

-- raise the budget from the box and buy the robe by clicking its row twice
ns.recipeBox:SetText("20g"); ns.recipeBox.__scripts.OnEnterPressed(ns.recipeBox); SIM.Advance(1)
L("budget now " .. ns.S.recipeBudget .. ", plan " .. #ns.RecipePlan())
local rowFor
for _, row in ipairs(ns.UI._rows()) do if row.data and row.data.itemID == 5003 then rowFor = row end end
if rowFor then rowFor:Click(); SIM.Advance(1.2); rowFor:Click(); SIM.Advance(1.2); rowFor:Click(); SIM.Advance(1.2) else L("robe row not found") end
L(("after row buy: spent %d, bids %d"):format(ns.db.recipeSpent, #(SIM.bids or {})))
for _, row in ipairs(ns.UI._rows()) do
    if row.data and row.__scripts.OnEnter then
        local ok, err = xpcall(function() row.__scripts.OnEnter(row) end, debug.traceback)
        if not ok then SIM.errors[#SIM.errors + 1] = "recipe tooltip: " .. err end
    end
end
SlashCmdList.DEPOSITWISE("recipemax reset"); SlashCmdList.DEPOSITWISE("recipemax")
for _, k in ipairs({ "BAGS", "DEALS", "MOVERS", "SMELT", "CRAFT", "SESSION", "AUCTIONS", "RECIPES" }) do ns.UI.SetTab(k); SIM.Advance(0.3) end
L("tabs ok, more label: " .. (f.moreTab:GetText() or ""))
