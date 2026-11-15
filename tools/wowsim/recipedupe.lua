-- TwizAH: never buy a recipe twice (pending buys, mailbox, same name), and learn recipes unattended
ADDON_DIR = REPO .. "/TwizAH"
dofile(REPO .. "/tools/wowsim/scenario.lua")
local ns = TwizAH
local L = function(s) SIM.log[#SIM.log + 1] = s end
GetProfessions = function() return 1 end
GetProfessionInfo = function() return "Tailoring", 0, 120 end
SIM.tooltipLines = SIM.tooltipLines or {}
local function recipe(id, name, price)
    SIM.items[id] = { name = name, vendor = 10, classID = 9, subID = 2, quality = 1 }
    SIM.tooltipLines[id] = { "Requires Tailoring (50)" }
    SIM.ah[id] = { commodity = false, listings = { { unit = price, qty = 1, auctionID = id * 10 }, { unit = price + 50, qty = 1, auctionID = id * 10 + 1 } } }
    ns.db.market[id] = { min = price, med = price, n = 2, q = 2, t = time() }
end
recipe(8001, "Pattern: Slow Server", 1000)   -- the buy goes through, but the gold change arrives late
recipe(8002, "Pattern: In Mailbox", 1100)
recipe(8003, "Pattern: Twin", 1200)
recipe(8004, "Pattern: Twin", 1300)          -- same recipe, another item ID
SIM.mail = { { sender = "Auction House", subject = "Auction won", items = { { id = 8002, count = 1 } } } }
MailFrame.__shown = true; SIM.Fire("MAIL_SHOW"); SIM.Fire("MAIL_INBOX_UPDATE"); SIM.Advance(1)
MailFrame.__shown = false; SIM.Fire("MAIL_CLOSED"); SIM.Advance(1)
SIM.onPlaceBid = function(auctionID, amount)
    -- every buy succeeds, but the server takes 7 seconds to take the gold
    for i, l in ipairs(SIM.ah[math.floor(auctionID / 10)].listings) do if l.auctionID == auctionID then table.remove(SIM.ah[math.floor(auctionID / 10)].listings, i) break end end
    C_Timer.After(7, function() SIM.money = SIM.money - amount; SIM.Fire("PLAYER_MONEY") end)
end
AuctionHouseFrame.__shown = true; SIM.Fire("AUCTION_HOUSE_SHOW"); SIM.Advance(10)
ns.S.recipeBudget = 100000; ns.db.recipeSpent = 0
local f = ns.UI._frame(); f:Show(); ns.UI.SetTab("RECIPES"); SIM.Advance(1)
local function names() local t = {} for _, r in ipairs(ns.RecipeList()) do t[#t + 1] = SIM.items[r.itemID].name .. "#" .. r.itemID end return table.concat(t, ", ") end
L("list: " .. names())
ns.extraTabs.RECIPES.__buttons[1]:Click(); SIM.Advance(1)
for i = 1, 40 do if ns.recipeRun then SIM.Wheel(); SIM.Advance(1) end end
SIM.Advance(10)
local per = {}
for _, b in ipairs(SIM.bids or {}) do local id = math.floor(b.id / 10) per[id] = (per[id] or 0) + 1 end
local t = {} for id, n in pairs(per) do t[#t + 1] = id .. "x" .. n end table.sort(t)
L("bids per recipe: " .. table.concat(t, " "))
L("list after: " .. names())
-- unattended learning once the AH closes
AuctionHouseFrame.__shown = false; SIM.Fire("AUCTION_HOUSE_CLOSED"); SIM.Advance(1)
local used = {}
local realUse = C_Container.UseContainerItem
C_Container.UseContainerItem = function(bag, slot)
    local sl = SIM.bags[bag .. ":" .. slot]
    if sl and SIM.items[sl.id].classID == 9 then
        used[#used + 1] = SIM.items[sl.id].name
        SIM.bags[bag .. ":" .. slot] = nil
        C_Timer.After(0.5, function() SIM.Fire("NEW_RECIPE_LEARNED"); SIM.Fire("BAG_UPDATE_DELAYED") end)
        return
    end
    return realUse(bag, slot)
end
SIM.PutInBags(8001, 1); SIM.PutInBags(8003, 1)
SIM.Fire("TRADE_SHOW"); SIM.Fire("BAG_UPDATE_DELAYED"); SIM.Advance(3)
L("while trading, used: " .. #used)
SIM.Fire("TRADE_CLOSED"); SIM.Advance(6)
L("after trade closes, learned: " .. table.concat(used, ", "))
