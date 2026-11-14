-- End-to-end scenario: login, AH bag scan, two full scans, every tab, tooltips, merchant, mail.
local ADDON_DIR = ADDON_DIR
local USE_REAL_SV = USE_REAL_SV

-- items: id = { name, vendor, classID, subID, quality }
local function item(id, name, vendor, classID, subID, extra)
    SIM.items[id] = { name = name, vendor = vendor, classID = classID or 7, subID = subID or 0, quality = 1 }
    if extra then for k, v in pairs(extra) do SIM.items[id][k] = v end end
end
item(2589, "Linen Cloth", 13, 7, 5)
item(2592, "Wool Cloth", 33, 7, 5)
item(2770, "Copper Ore", 5, 7, 7)
item(2840, "Copper Bar", 10, 7, 7)
item(2771, "Tin Ore", 25, 7, 7)
item(1206, "Moss Agate", 100, 7, 4)
item(10940, "Strange Dust", 25, 7, 12)
item(2320, "Coarse Thread", 2, 7, 5)
item(2996, "Bolt of Linen Cloth", 40, 7, 5)
item(4238, "Linen Bag", 100, 1, 0)
item(2207, "Jambiya", 1200, 2, 15, { gear = true })
item(2901, "Mining Pick", 16, 2, 0)
item(5503, "Clam Meat", 12, 7, 8)
item(4357, "Rough Blasting Powder", 4, 7, 1)
item(9999, "Junk Rock", 50, 15, 0)
item(15807, "Light Crossbow", 900, 2, 18, { gear = true, uncached = true })

local function list(id, commodity, ls) SIM.ah[id] = { commodity = commodity, listings = ls } end
list(2589, true, { { unit = 50, qty = 20, timeLeft = 2 }, { unit = 55, qty = 40, timeLeft = 3 }, { unit = 70, qty = 100, timeLeft = 3 } })
list(2592, true, { { unit = 20, qty = 10, timeLeft = 2 }, { unit = 120, qty = 30, timeLeft = 3 }, { unit = 125, qty = 50, timeLeft = 3 }, { unit = 130, qty = 50, timeLeft = 2 } })
list(2770, true, { { unit = 30, qty = 40, timeLeft = 3 }, { unit = 32, qty = 60, timeLeft = 2 } })
list(2840, true, { { unit = 90, qty = 20, timeLeft = 3 } })
list(1206, true, { { unit = 900, qty = 3, timeLeft = 3 }, { unit = 950, qty = 2, timeLeft = 2 }, { unit = 1000, qty = 5, timeLeft = 3 } })
list(10940, true, { { unit = 200, qty = 12, timeLeft = 3 }, { unit = 220, qty = 20, timeLeft = 3 }, { unit = 250, qty = 10, timeLeft = 1 } })
list(2996, true, { { unit = 400, qty = 10, timeLeft = 3 } })
list(2207, false, { { unit = 3000, qty = 1, timeLeft = 2 }, { unit = 3500, qty = 1, timeLeft = 3, minBid = 500, noBuyout = false }, { unit = 9000, qty = 1, timeLeft = 0, minBid = 300 } })
list(15807, false, { { unit = 5000, qty = 1, timeLeft = 3, minBid = 200 } })
list(5503, true, { { unit = 8, qty = 50, timeLeft = 3 } })
list(4357, true, { { unit = 30, qty = 20, timeLeft = 3 } })

SIM.PutInBags(2589, 20)
SIM.PutInBags(2770, 15)
SIM.PutInBags(1206, 2)
SIM.PutInBags(5503, 10)   -- AH 8 net 7.6 < vendor 12 -> vendor
SIM.PutInBags(9999, 1)    -- no AH listing
SIM.PutInBags(2901, 1)    -- tool, never sell
SIM.PutInBags(2207, 1)
SIM.PutInBags(2320, 5)
SIM.merchant = { { id = 2320, price = 10, stack = 1 }, { id = 2589, price = 100, stack = 1 } }
SIM.quests = { { title = "Wool Drive", questID = 7, isHeader = false } }
SIM.quests[1].objectives = { { type = "item", text = "Wool Cloth: 2/10" } }

if USE_REAL_SV then dofile(USE_REAL_SV) end

local ns = SIM.LoadAddon(ADDON_DIR, "DepositWise")
local T0 = os.clock()
SIM.Fire("ADDON_LOADED", "DepositWise")
SIM.Fire("PLAYER_LOGIN")
SIM.Fire("PLAYER_ENTERING_WORLD", true, false)
SIM.Advance(2)
local function step(label) SIM.log[#SIM.log + 1] = "=== " .. label end

step("open AH")
AuctionHouseFrame.__shown = true
SIM.Fire("AUCTION_HOUSE_SHOW")
SIM.Advance(15)

step("visit every tab")
local function visitTabs()
    for _, key in ipairs({ "BRIEF", "BAGS", "DEALS", "MOVERS", "SMELT", "CRAFT", "SESSION", "AUCTIONS" }) do
        if ns.UI and ns.UI.SetTab then
            local ok, err = xpcall(function() ns.UI.SetTab(key); ns.UI.Refresh() end, debug.traceback)
            if not ok then SIM.errors[#SIM.errors + 1] = "tab " .. key .. ": " .. err end
        end
    end
end
if ns.UI and ns.UI.Show then ns.UI.Show() end
visitTabs()

step("full scan 1")
SlashCmdList.DEPOSITWISE("fullscan")
SIM.Advance(20)
-- market moves: some linen sells, wool undercut + repost, dust short listing expires
SIM.ah[2589].listings[1].qty = 5
table.remove(SIM.ah[10940].listings, 3)
table.insert(SIM.ah[2592].listings, { unit = 110, qty = 30, timeLeft = 3 })
SIM.now = SIM.now + 20 * 60
SIM.gt = SIM.gt + 20 * 60
step("full scan 2")
SlashCmdList.DEPOSITWISE("fullscan")
SIM.Advance(20)
visitTabs()

step("tooltips on all rows")
-- hover every visible row on each tab
if ns.UI and ns.UI._rows then
    for _, key in ipairs({ "BAGS", "DEALS", "CRAFT", "MOVERS", "SMELT", "AUCTIONS" }) do
        ns.UI.SetTab(key); ns.UI.Refresh()
        for _, row in ipairs(ns.UI._rows()) do
            local f = row.__scripts and row.__scripts.OnEnter
            if f and row.data then local ok, err = xpcall(function() f(row) end, debug.traceback) if not ok then SIM.errors[#SIM.errors + 1] = "tooltip " .. key .. ": " .. err end end
        end
    end
end
if SIM.tooltipPost then
    for id in pairs(SIM.items) do local ok, err = xpcall(function() SIM.tooltipPost(GameTooltip, { id = id }) end, debug.traceback) if not ok then SIM.errors[#SIM.errors + 1] = "itemtooltip: " .. err end end
end

step("post next best x3")
for i = 1, 3 do SIM.gt = SIM.gt + 1; if ns.PostNextBest then ns.PostNextBest() end SIM.Advance(1) end

step("close AH")
AuctionHouseFrame.__shown = false
SIM.Fire("AUCTION_HOUSE_CLOSED")
SIM.Advance(1)

step("merchant")
SIM.OpenMerchant()
SIM.Advance(5)
SIM.CloseMerchant()

step("mail")
SIM.mail = {
    { sender = "Alliance Auction House", subject = "Auction successful: Linen Cloth", money = 950,
      invoice = { type = "seller", itemName = "Linen Cloth", buyer = "Bob", bid = 1000, buyout = 1000, deposit = 20, consignment = 50, count = 20 } },
    { sender = "Alliance Auction House", subject = "Auction expired: Copper Ore", items = { { id = 2770, count = 15 } } },
    { sender = "Friend", subject = "hi", money = 100 },
}
MailFrame.__shown = true
SIM.Fire("MAIL_SHOW")
SIM.Fire("MAIL_INBOX_UPDATE")
SIM.Advance(3)
if ns.CollectAHMail then ns.CollectAHMail() SIM.Advance(10) end
MailFrame.__shown = false
SIM.Fire("MAIL_CLOSED")

step("my auctions")
AuctionHouseFrame.__shown = true
SIM.Fire("AUCTION_HOUSE_SHOW")
SIM.owned = {
    { auctionID = 501, itemKey = C_AuctionHouse.MakeItemKey(2589), itemLink = select(2, C_Item.GetItemInfo(2589)), status = 0, quantity = 20, timeLeftSeconds = 20000, buyoutAmount = 60 },
    { auctionID = 502, itemKey = C_AuctionHouse.MakeItemKey(1206), itemLink = select(2, C_Item.GetItemInfo(1206)), status = 0, quantity = 2, timeLeftSeconds = 900, buyoutAmount = 1200 },
    { auctionID = 503, itemKey = C_AuctionHouse.MakeItemKey(2770), itemLink = select(2, C_Item.GetItemInfo(2770)), status = 1, quantity = 10, buyoutAmount = 30 },
}
ns.UI.SetTab("AUCTIONS")
SIM.Advance(10)
for _, a in ipairs(ns.owned or {}) do SIM.log[#SIM.log + 1] = ("owned %d %s ahead=%s other=%s cancel=%s :: %s"):format(a.auctionID, a.status, tostring(a.ahead), tostring(a.otherLow), tostring(a.cancel), tostring(a.reason)) end
if ns.CancelNextUndercut then ns.CancelNextUndercut() SIM.Advance(1) end
for _, row in ipairs(ns.UI._rows()) do if row.data and row.__scripts.OnEnter then local ok, err = xpcall(function() row.__scripts.OnEnter(row) end, debug.traceback) if not ok then SIM.errors[#SIM.errors+1] = "auction tooltip: " .. err end end end
AuctionHouseFrame.__shown = false
SIM.Fire("AUCTION_HOUSE_CLOSED")

step("stats")
local db = DepositWiseDB
local o = {}
for id, v in pairs(db.outcomes or {}) do o[#o + 1] = id .. "=" .. v.s .. "/" .. v.e end
SIM.log[#SIM.log + 1] = "outcomes: " .. table.concat(o, " ")
local mr = db.myRates
SIM.log[#SIM.log + 1] = ("myRates 2h %d/%d 8h %d/%d 24h %d/%d"):format(mr[1].s, mr[1].e, mr[2].s, mr[2].e, mr[3].s, mr[3].e)
local pend = 0 for n, l in pairs(db.pendingPosts) do pend = pend + #l end
SIM.log[#SIM.log + 1] = "pending posts: " .. pend .. "  money now: " .. SIM.money
step("logout")
SIM.Fire("PLAYER_LOGOUT")
local hs = 0 for _, h in pairs(DepositWiseDB.history or {}) do if type(h) == "string" then hs = hs + 1 end end
SIM.log[#SIM.log + 1] = "compacted history entries: " .. hs .. " rates type: " .. type(select(2, next(DepositWiseDB.rates or {})))
SIM_RESULT_CPU = os.clock() - T0
