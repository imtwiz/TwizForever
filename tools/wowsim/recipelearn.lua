-- TwizAH: Refresh prices (drops sold recipes, instant buys from fresh prices) and the Learn button
ADDON_DIR = REPO .. "/TwizAH"
dofile(REPO .. "/tools/wowsim/scenario.lua")
local ns = TwizAH
local L = function(s) SIM.log[#SIM.log + 1] = s end
GetProfessions = function() return 1 end
GetProfessionInfo = function() return "Tailoring", 0, 120 end
SIM.tooltipLines = SIM.tooltipLines or {}
local function recipe(id, name, price, listings, level)
    SIM.items[id] = { name = name, vendor = 10, classID = 9, subID = 2, quality = 1 }
    SIM.tooltipLines[id] = { "Requires Tailoring (" .. (level or 50) .. ")" }
    SIM.ah[id] = { commodity = false, listings = listings or { { unit = price, qty = 1, auctionID = id * 10 } } }
    ns.db.market[id] = { min = price, med = price, n = 1, q = 1, t = time() }
end
recipe(7001, "Pattern: One", 1000)
recipe(7002, "Pattern: Sold Since Scan", 1200, {})
recipe(7003, "Pattern: Two", 1500)
SIM.onPlaceBid = function(auctionID, amount)
    SIM.money = SIM.money - amount
    C_Timer.After(0.3, function() SIM.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", auctionID) end)
end
AuctionHouseFrame.__shown = true; SIM.Fire("AUCTION_HOUSE_SHOW"); SIM.Advance(1)
ns.S.recipeBudget = 100000; ns.db.recipeSpent = 0
local f = ns.UI._frame(); f:Show(); ns.UI.SetTab("RECIPES"); SIM.Advance(1)
local function names() local t = {} for _, r in ipairs(ns.RecipeList()) do t[#t + 1] = SIM.items[r.itemID].name end return table.concat(t, ", ") end
L("before refresh: " .. names())
local btns = ns.extraTabs.RECIPES.__buttons
L("refresh button: " .. btns[2]:GetText())
btns[2]:Click(); SIM.Advance(0.2); L("while refreshing: " .. btns[2]:GetText())
SIM.Advance(20)
L("after refresh: " .. names() .. " | button " .. btns[2]:GetText())
-- buying now goes straight to confirm: no search per recipe
local searches = 0
local realSend = C_AuctionHouse.SendSearchQuery
C_AuctionHouse.SendSearchQuery = function(...) searches = searches + 1 return realSend(...) end
btns[1]:Click(); SIM.Advance(0.1)
L("first press -> stage " .. tostring(ns.recipeBuy and ns.recipeBuy.stage))
for i = 1, 6 do if ns.recipeRun then SIM.Wheel(); SIM.Advance(0.5) end end
L(("bought %d, searches during run %d, spent %d"):format(#(SIM.bids or {}), searches, ns.db.recipeSpent))
-- recipes arrive in the bags (from the mailbox): Learn button + mouse wheel at the mailbox
AuctionHouseFrame.__shown = false; SIM.Fire("AUCTION_HOUSE_CLOSED"); SIM.Advance(1)
SIM.PutInBags(7001, 1); SIM.PutInBags(7003, 1)
recipe(7009, "Pattern: Too High", 100, nil, 200); SIM.PutInBags(7009, 1)
MailFrame.__shown = true; SIM.Fire("MAIL_SHOW"); SIM.Fire("BAG_UPDATE_DELAYED"); SIM.Advance(1)
local b = TwizAHLearnButton
L(("learn button shown=%s text=%s macro=%s wheel=%s"):format(tostring(b.__shown), b.text:GetText() or "", tostring(b:GetAttribute("macrotext")), tostring(SIM.overrides["MOUSEWHEELDOWN"])))
MailFrame.__shown = false; SIM.Fire("MAIL_CLOSED"); SIM.Advance(1)
L("after mailbox closes: wheel=" .. tostring(SIM.overrides["MOUSEWHEELDOWN"]) .. " shown=" .. tostring(b.__shown))
SIM.TakeFromBags(7001, 1); SIM.TakeFromBags(7003, 1); SIM.Fire("BAG_UPDATE_DELAYED"); SIM.Advance(1)
L("all learned: shown=" .. tostring(b.__shown))
