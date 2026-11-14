-- TwizCraft shopping: the cheapest shopping route, and buying from vendors
-- (one click buys everything on your list) and the AH (click to get the
-- price, click again to confirm - the game requires a click per purchase).
local ADDON, NS = ...

------------------------------------------------------------------------
-- Questie (through TwizQuest) knows which vendors sell what, and where
------------------------------------------------------------------------
local function QR()
    if TwizQuest and TwizQuest.Bridge and TwizQuest.Bridge() then return TwizQuest end
end

local function Faction()
    return UnitFactionGroup("player") == "Horde" and "H" or "A"
end

-- friendly vendors that sell this item; with inst, only spawns on that continent
local function Vendors(id, inst)
    local R = QR()
    if not R then return {} end
    local list = R.I(id, "vendors")
    local out, f = {}, Faction()
    for _, npc in ipairs(type(list) == "table" and list or {}) do
        local fr = R.N(npc, "friendlyToFaction")
        if type(fr) == "string" and fr:find(f, 1, true) then
            if not inst then
                out[#out + 1] = { npc = npc, name = R.N(npc, "name") }
            else
                local spawns = R.N(npc, "spawns")
                for areaId, pts in pairs(type(spawns) == "table" and spawns or {}) do
                    for _, c in ipairs(type(pts) == "table" and pts or {}) do
                        if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and c[1] > 0 then
                            local wx, wy, i, map = R.World(areaId, c[1], c[2])
                            if wx and i == inst then
                                out[#out + 1] = { npc = npc, name = R.N(npc, "name"), x = wx, y = wy,
                                                  map = map, mx = c[1], my = c[2] }
                            end
                        end
                    end
                end
            end
        end
    end
    return out
end

-- Vendor price you haven't seen yet: vendors charge about 4x what they pay you
function NS.QuestieVendorPrice(id)
    if #Vendors(id) > 0 then
        local sell = NS.VendorSell(id)
        if sell > 0 then return sell * 4 end
    end
end

------------------------------------------------------------------------
-- The route
------------------------------------------------------------------------
-- Returns ordered stops: { kind, label, items = { {id, n} }, cost, x, y, map, mx, my, dist }
function NS.ShoppingRoute(plan)
    local stops = {}
    if not plan or not plan.shop then return stops end
    local R = QR()
    local px, py, inst
    if R then px, py, inst = R.PlayerPos() end

    local ah, farm, vend, bank, mail = {}, {}, {}, {}, {}
    for _, e in ipairs(plan.shop) do
        local short = e.need - e.bags - e.bank
        if (e.mail or 0) > 0 and short > 0 then
            table.insert(mail, { id = e.id, n = math.min(e.mail, short) })
        end
        if e.bank > 0 and e.bags < e.need then
            table.insert(bank, { id = e.id, n = math.min(e.bank, e.need - e.bags) })
        end
        if e.buy > 0 then
            if e.src == "AH" then table.insert(ah, e)
            elseif e.src == "vendor" then table.insert(vend, e)
            elseif e.src == "farm" then table.insert(farm, e) end
        end
    end

    -- bank
    if #bank > 0 then
        local s = { kind = "bank", label = "Bank: take out", items = bank, cost = 0 }
        local b = R and R.NearestBank and inst and R.NearestBank(inst, px, py)
        if b then s.x, s.y, s.map, s.mx, s.my = b.x, b.y, b.map, b.mx, b.my end
        stops[#stops + 1] = s
    end

    -- mailbox: AH purchases waiting to be picked up
    if #mail > 0 then
        local s = { kind = "mail", label = "Mailbox: pick up", items = mail, cost = 0 }
        local m = inst and NS.NearestMailbox and NS.NearestMailbox(inst, px, py)
        if m then s.x, s.y, s.map, s.mx, s.my = m.x, m.y, m.map, m.mx, m.my end
        stops[#stops + 1] = s
    end

    -- vendors: fewest stops that cover everything, nearer ones first
    local left = {}
    for _, e in ipairs(vend) do left[e.id] = e end
    local cands = {}  -- npc -> { spawn, items }
    if R and inst then
        for _, e in ipairs(vend) do
            for _, v in ipairs(Vendors(e.id, inst)) do
                local c = cands[v.npc]
                local d = NS.Dist2(px, py, v.x, v.y)
                if not c then c = { v = v, d = d, items = {} }; cands[v.npc] = c end
                if d < c.d then c.v, c.d = v, d end
                c.items[e.id] = true
            end
        end
    end
    while next(left) do
        local best, bestN, bestD
        for _, c in pairs(cands) do
            local n = 0
            for id in pairs(c.items) do if left[id] then n = n + 1 end end
            if n > 0 and (not best or n > bestN or (n == bestN and c.d < bestD)) then best, bestN, bestD = c, n, c.d end
        end
        if not best then break end
        local s = { kind = "vendor", label = "Vendor: " .. (best.v.name or "?"), items = {}, cost = 0,
                    x = best.v.x, y = best.v.y, map = best.v.map, mx = best.v.mx, my = best.v.my }
        for id in pairs(best.items) do
            local e = left[id]
            if e then
                table.insert(s.items, { id = id, n = e.buy }); s.cost = s.cost + e.cost
                left[id] = nil
            end
        end
        stops[#stops + 1] = s
    end
    -- vendor items Questie can't place: group by the merchant you saw sell it
    local byName = {}
    for id, e in pairs(left) do
        local who = (e.extra and e.extra.npc) and (e.extra.npc .. (e.extra.zone and (", " .. e.extra.zone) or "")) or "a vendor"
        byName[who] = byName[who] or { kind = "vendor", label = "Vendor: " .. who, items = {}, cost = 0 }
        table.insert(byName[who].items, { id = id, n = e.buy }); byName[who].cost = byName[who].cost + e.cost
    end
    for _, s in pairs(byName) do stops[#stops + 1] = s end

    -- auction house
    if #ah > 0 then
        local s = { kind = "ah", label = "Auction House", items = {}, cost = 0 }
        for _, e in ipairs(ah) do table.insert(s.items, { id = e.id, n = e.buy }); s.cost = s.cost + e.cost end
        local spot = NS.db.ahSpots and inst and NS.db.ahSpots[inst]
        if spot then s.x, s.y, s.map, s.mx, s.my = spot.x, spot.y, spot.map, spot.mx, spot.my end
        stops[#stops + 1] = s
    end

    -- order the stops we can place: always go to the nearest next
    if px then
        local placed, unplaced = {}, {}
        for _, s in ipairs(stops) do
            if s.x then placed[#placed + 1] = s else unplaced[#unplaced + 1] = s end
        end
        local ordered, cx, cy = {}, px, py
        while #placed > 0 do
            local bi, bd
            for i, s in ipairs(placed) do
                local d = NS.Dist2(cx, cy, s.x, s.y)
                if not bd or d < bd then bi, bd = i, d end
            end
            local s = table.remove(placed, bi)
            s.dist = bd
            ordered[#ordered + 1] = s
            cx, cy = s.x, s.y
        end
        for _, s in ipairs(unplaced) do ordered[#ordered + 1] = s end
        stops = ordered
    end

    -- things to make and gather come after shopping
    for _, sc in ipairs(plan.subcrafts or {}) do
        stops[#stops + 1] = { kind = "make", label = ("%sMake %d %s"):format(sc.learn and "Learn at trainer, then " or "", sc.n, sc.name), items = {}, cost = 0, sub = sc }
    end
    if #farm > 0 then
        local s = { kind = "farm", label = "Gather / farm", items = {}, cost = 0 }
        for _, e in ipairs(farm) do table.insert(s.items, { id = e.id, n = e.buy }) end
        stops[#stops + 1] = s
    end
    return stops
end

function NS.Dist2(ax, ay, bx, by)
    if not (ax and bx) then return math.huge end
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

function NS.Waypoint(s)
    if not s or not s.map then return end
    if TomTom and TomTom.AddWaypoint then
        if NS.wayUID and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, NS.wayUID) end
        local ok, uid = pcall(TomTom.AddWaypoint, TomTom, s.map, s.mx / 100, s.my / 100,
            { title = s.label, from = "TwizCraft", persistent = false, crafty = true })
        if ok then NS.wayUID = uid end
    elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint then
        pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(s.map, s.mx / 100, s.my / 100))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
    end
    NS.Print("waypoint: " .. s.label)
end

------------------------------------------------------------------------
-- Buying from a vendor (one click buys all of it, one purchase at a time)
------------------------------------------------------------------------
NS.merchantOpen, NS.ahOpen = false, false
local queue, waiting

local function MerchantIndex()
    local idx = {}
    for i = 1, (GetMerchantNumItems() or 0) do
        local id = GetMerchantItemID and GetMerchantItemID(i)
        if id and not idx[id] then
            local price, stack, avail, ext
            if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
                local info = C_MerchantFrame.GetItemInfo(i)
                if info then price, stack, avail, ext = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
            else
                local _, _, p, q, n, _, _, e = GetMerchantItemInfo(i)
                price, stack, avail, ext = p, q, n, e
            end
            if price and not ext and avail ~= 0 then
                local chunk = (GetMerchantItemMaxStack and GetMerchantItemMaxStack(i)) or (stack or 1)
                idx[id] = { index = i, price = price, bundle = math.max(1, stack or 1), avail = avail or -1,
                            chunk = math.max(stack or 1, chunk) }
            end
        end
    end
    return idx
end

-- What this vendor sells from your list: { {id, n, offer, cost} }, total
-- Amounts come from live counts (bags + bank + mailbox), not the last plan, so a
-- purchase that just landed (ours or TwizChef's) is never bought a second time.
function NS.VendorCart(plan)
    local cart, total = {}, 0
    if not (plan and plan.shop and NS.merchantOpen) then return cart, 0 end
    local idx = MerchantIndex()
    for _, e in ipairs(plan.shop) do
        local o = idx[e.id]
        local want = e.buy
        if e.need then want = math.min(want, math.max(0, e.need - NS.Owned(e.id))) end
        -- buy here if it's on the list and this vendor is the cheapest way to get it
        if o and want > 0 and (e.src == "vendor" or e.src == "farm" or o.price / o.bundle <= (e.unit or math.huge)) then
            local purchases = math.ceil(want / o.bundle)
            if o.avail > 0 then purchases = math.min(purchases, o.avail) end
            local c = { id = e.id, n = purchases * o.bundle, offer = o, cost = purchases * o.price }
            cart[#cart + 1] = c; total = total + c.cost
        end
    end
    return cart, total
end

-- true while either Twiz addon is buying from a vendor
function NS.VendorBusy() return queue ~= nil end
local function OtherBusy() return TwizChef and TwizChef.Busy and TwizChef.Busy() end

local function StopVendor(msg)
    queue, waiting = nil, nil
    if msg then NS.Print(msg) end
    if NS.Replan then NS.Replan(true) end
    if NS.RefreshUI then NS.RefreshUI() end
end

-- Each job buys until the bags hold job.goal: re-checked before every purchase,
-- so nothing is double-counted even if a purchase arrives late or in pieces.
local function NextVendorBuy()
    if not queue or waiting then return end
    if not NS.merchantOpen then return StopVendor("vendor closed, stopped buying.") end
    local job = queue[1]
    if not job then return StopVendor("done buying from this vendor.") end
    local left = job.goal - NS.BagCount(job.id)
    if left <= 0 then table.remove(queue, 1); return NextVendorBuy() end
    local o = job.offer
    if GetMerchantItemID(o.index) ~= job.id then return StopVendor("vendor list changed, stopped.") end
    local amount
    if o.bundle > 1 then
        amount = o.bundle                    -- one bundle per purchase: no quantity ambiguity
    else
        amount = math.min(left, o.chunk)
    end
    if GetMoney() < math.ceil(amount / o.bundle) * o.price then return StopVendor("not enough gold.") end
    waiting = { id = job.id, before = NS.BagCount(job.id), amount = amount }
    local token = waiting
    if o.bundle > 1 then BuyMerchantItem(o.index) else BuyMerchantItem(o.index, amount) end
    C_Timer.After(4, function() if waiting == token then StopVendor("a purchase didn't arrive (bags full?), stopped.") end end)
end

local function StartVendor(cart)
    if queue then NS.Print("already buying - wait for it to finish."); return end
    if OtherBusy() then NS.Print("TwizChef is buying here right now - try again when it's done."); return end
    queue = {}
    for _, c in ipairs(cart) do
        queue[#queue + 1] = { id = c.id, offer = c.offer, goal = NS.BagCount(c.id) + c.n }
    end
    if NS.RefreshUI then NS.RefreshUI() end
    NextVendorBuy()
end

StaticPopupDialogs["CRAFTROUTE_VENDOR"] = {
    text = "TwizCraft: spend %s at this vendor on crafting supplies?",
    button1 = YES or "Yes", button2 = NO or "No",
    -- rebuild the cart on accept: counts may have changed while the popup was up
    OnAccept = function(_, plan)
        local cart = NS.VendorCart(plan)
        if #cart > 0 then StartVendor(cart) end
    end,
    timeout = 0, hideOnEscape = true, preferredIndex = 3,
}

function NS.BuyFromVendor(plan)
    if queue then NS.Print("already buying - wait for it to finish."); return end
    if OtherBusy() then NS.Print("TwizChef is buying here right now - try again when it's done."); return end
    local cart, total = NS.VendorCart(plan)
    if #cart == 0 then NS.Print("nothing left to buy here - you already have it."); return end
    if total > (NS.db.confirmOver or 50000) then
        StaticPopup_Show("CRAFTROUTE_VENDOR", NS.Money(total), nil, plan)
    else
        StartVendor(cart)
    end
end

------------------------------------------------------------------------
-- Buying on the AH: click to get the price, click again to confirm
------------------------------------------------------------------------
NS.ah = { state = nil }   -- nil | "pricing" | "confirm" | "buying"
local skipped = {}

function NS.NextAHItem(plan)
    for _, e in ipairs(plan and plan.shop or {}) do
        if e.buy > 0 and e.src == "AH" and not skipped[e.id] then return e end
    end
end

function NS.AHClick(plan, button)
    local A = NS.ah
    if button == "RightButton" then
        if A.state then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
        if A.item then skipped[A.item.id] = true; NS.Print("skipped " .. NS.ItemName(A.item.id)) end
        A.state, A.item = nil, nil
        return
    end
    if A.state == "confirm" then
        A.state = "buying"
        C_AuctionHouse.ConfirmCommoditiesPurchase(A.item.id, A.item.buy)
        return
    end
    if A.state then return end
    local e = NS.NextAHItem(plan)
    if not e then NS.Print("nothing left to buy on the AH."); return end
    A.item, A.state = e, "pricing"
    C_AuctionHouse.StartCommoditiesPurchase(e.id, e.buy)
    C_Timer.After(5, function()
        if A.state == "pricing" and A.item == e then
            A.state = nil; skipped[e.id] = true
            NS.Print(("no price for %s - maybe not enough listed. Skipped."):format(NS.ItemName(e.id)))
            if NS.RefreshUI then NS.RefreshUI() end
        end
    end)
end

function NS.AHButtonText(plan)
    local A = NS.ah
    if A.state == "pricing" then return "Getting price..." end
    if A.state == "confirm" then
        local each = A.total / math.max(1, A.item.buy)
        local high = A.item.unit and each > A.item.unit * 1.5
        return ("%sConfirm: %d %s for %s|r"):format(high and "|cffff4040" or "|cff40ff40", A.item.buy,
            NS.ItemName(A.item.id), NS.Money(A.total)), high
    end
    if A.state == "buying" then return "Buying..." end
    local e = NS.NextAHItem(plan)
    if not e then return nil end
    return ("Buy on AH: %d %s (~%s)"):format(e.buy, NS.ItemName(e.id), NS.Money(e.cost))
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local f = CreateFrame("Frame")
for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "BAG_UPDATE_DELAYED", "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
    "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED" }) do
    pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event, a1, a2)
    if not NS.db then return end
    local A = NS.ah
    if event == "MERCHANT_SHOW" then
        NS.merchantOpen = true
        C_Timer.After(0.6, function() if NS.Replan then NS.Replan(true) end end)
    elseif event == "MERCHANT_CLOSED" then
        NS.merchantOpen = false
        if queue then StopVendor() end
    elseif event == "AUCTION_HOUSE_SHOW" then
        NS.ahOpen = true
        -- remember where this AH is, for the route
        local R = QR()
        if R then
            local x, y, inst = R.PlayerPos()
            local map = C_Map.GetBestMapForUnit("player")
            local pos = map and C_Map.GetPlayerMapPosition(map, "player")
            if x and pos then
                local mx, my = pos:GetXY()
                NS.db.ahSpots = NS.db.ahSpots or {}
                NS.db.ahSpots[inst] = { x = x, y = y, map = map, mx = mx * 100, my = my * 100 }
            end
        end
        if NS.RefreshUI then NS.RefreshUI() end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        NS.ahOpen = false
        if A.state then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
        A.state, A.item = nil, nil
        if NS.RefreshUI then NS.RefreshUI() end
    elseif event == "BAG_UPDATE_DELAYED" then
        if waiting and NS.BagCount(waiting.id) - waiting.before >= waiting.amount then
            waiting = nil
            C_Timer.After(0.15, NextVendorBuy)
        elseif not queue and NS.merchantOpen and NS.Replan then
            NS.Replan()          -- e.g. TwizChef just bought something: refresh the list
        end
    elseif event == "COMMODITY_PRICE_UPDATED" then
        if A.state == "pricing" then
            A.state, A.unitPrice, A.total = "confirm", a1, a2
            if NS.RefreshUI then NS.RefreshUI() end
        end
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
        if A.state == "pricing" and A.item then
            skipped[A.item.id] = true
            NS.Print(("not enough %s on the AH right now - skipped."):format(NS.ItemName(A.item.id)))
            A.state, A.item = nil, nil
            if NS.RefreshUI then NS.RefreshUI() end
        end
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        if A.state == "buying" then
            NS.Print(("bought %d %s - it's waiting in your mailbox."):format(A.item.buy, NS.ItemName(A.item.id)))
            if NS.NoteMailed then NS.NoteMailed(A.item.id, A.item.buy) end
            A.state, A.item = nil, nil
            -- update the list right away: it's no longer something to buy
            if NS.Replan then NS.Replan(true) end
            if NS.RefreshUI then NS.RefreshUI() end
        end
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        if A.state == "buying" then
            NS.Print("purchase failed (prices may have changed) - click to try again.")
            A.state, A.item = nil, nil
            if NS.RefreshUI then NS.RefreshUI() end
        end
    end
end)
