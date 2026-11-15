-- TwizAH Buy All Recipes run: gone listings, sniped listings, overpriced ones are skipped and the
-- run keeps going by itself; each wheel notch buys one
ADDON_DIR = REPO .. "/TwizAH"
dofile(REPO .. "/tools/wowsim/scenario.lua")
local ns = TwizAH
local L = function(s) SIM.log[#SIM.log + 1] = s end
GetProfessions = function() return 1 end
GetProfessionInfo = function() return "Tailoring", 0, 120 end
SIM.tooltipLines = SIM.tooltipLines or {}
local function recipe(id, name, price, listings)
    SIM.items[id] = { name = name, vendor = 10, classID = 9, subID = 2, quality = 1 }
    SIM.tooltipLines[id] = { "Requires Tailoring (50)" }
    SIM.ah[id] = { commodity = false, listings = listings or { { unit = price, qty = 1, auctionID = id * 10 }, { unit = price + 100, qty = 1, auctionID = id * 10 + 1 } } }
    ns.db.market[id] = { min = price, med = price, n = 2, q = 2, t = time() }
end
recipe(6001, "Pattern: A", 1000)
recipe(6002, "Pattern: Gone", 1500, {})                                   -- sold since the full scan
recipe(6003, "Pattern: Sniped", 2000)                                     -- cheapest listing bought by someone else mid-purchase
recipe(6004, "Pattern: Pricey", 2500, { { unit = 9000, qty = 1, auctionID = 60040 } }) -- now 3.6x usual
recipe(6005, "Pattern: E", 3000)
recipe(6006, "Pattern: Commodity", 3500, { { unit = 3500, qty = 5, auctionID = 60060 } })
SIM.ah[6006].commodity = true -- the game sells this one as a commodity
local realKeyInfo = C_AuctionHouse.GetItemKeyInfo
C_AuctionHouse.GetItemKeyInfo = function(key) if key.itemID == 6006 then return nil end return realKeyInfo(key) end -- not cached yet
local sniped = false
SIM.onPlaceBid = function(auctionID, amount)
    if auctionID == 60030 and not sniped then
        sniped = true; table.remove(SIM.ah[6003].listings, 1)
        C_Timer.After(0.3, function() SIM.Fire("AUCTION_HOUSE_SHOW_ERROR", 1) end); return
    end
    SIM.money = SIM.money - amount
    for i, l in ipairs(SIM.ah[math.floor(auctionID / 10)].listings) do if l.auctionID == auctionID then table.remove(SIM.ah[math.floor(auctionID / 10)].listings, i) break end end
    C_Timer.After(0.3, function() SIM.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", auctionID) end)
end
AuctionHouseFrame.__shown = true; SIM.Fire("AUCTION_HOUSE_SHOW"); SIM.Advance(1)
ns.S.recipeBudget = 200000; ns.db.recipeSpent = 0
local f = ns.UI._frame(); f:Show(); ns.UI.SetTab("RECIPES"); SIM.Advance(1)
L(("plan %d, button: %s"):format(#ns.RecipePlan(), ns.extraTabs.RECIPES.__buttons[1]:GetText()))
-- bag research is still running and the throttle gets stuck without telling anyone
for i = 1, 6 do ns.QueueLookup(2589, nil, true, function() end) end
SIM.throttleStuckUntil = GetTime() + 5
ns.extraTabs.RECIPES.__buttons[1]:Click(); SIM.Advance(1.5)       -- one click starts the run
L("wheel bound to: " .. tostring(SIM.overrides["MOUSEWHEELDOWN"]))
local notches = 0
for i = 1, 80 do
    if not ns.recipeRun then break end
    SIM.Wheel(); notches = notches + 1; SIM.Advance(0.5)
end
SIM.Advance(2)
L(("notches %d, bids %d, spent %d, run active %s, wheel now %s"):format(notches, #(SIM.bids or {}), ns.db.recipeSpent,
    tostring(ns.recipeRun ~= nil), tostring(SIM.overrides["MOUSEWHEELDOWN"])))
local left = {}
for _, r in ipairs(ns.RecipeList()) do left[#left + 1] = SIM.items[r.itemID].name end
L("still listed: " .. table.concat(left, ", "))
