-- DepositWise: Rates - learns how fast things actually sell
--
-- Two sources, blended per item:
--  1) Market trend: every full scan is compared to the previous one. For each
--     seller, how many units they had listed near the cheapest price and how
--     many are gone now = units bought. (Measured per seller, so cancel-and-
--     repost doesn't count as a sale.) Also counted: how often someone lists
--     below the cheapest price (undercut frequency).
--  2) Your own results: "A buyer has been found..." / "...has expired"
--     messages for items you posted.
--
-- Sell chance for a listing of q units lasting T hours:
--   time you stay cheapest  ~ (1 - e^(-uT)) / u   (u = undercuts per hour)
--   expected buyers         ~ Poisson(demand/hour x that time)
--   chance                  = expected share of your q units that sell
local ADDON, ns = ...

local HOURS = { 12, 24, 48 }
local MIN_GAP, MAX_GAP = 5 * 60, 6 * 3600   -- scan pairs further apart than 6h are too noisy
local CHEAP_BAND = 1.25                      -- "near the cheapest" = within 25% of the lowest price
local DECAY = 0.85                           -- older scan pairs fade out
local OWN_WEIGHT = 4                          -- market model counts as this many of your own auctions

local function DB()
    local db = ns.db
    db.rates = db.rates or {}        -- [itemID] = { u = units bought, h = hours watched, x = undercuts, n = scan pairs }
    db.outcomes = db.outcomes or {}  -- [itemID] = { s = sold, e = expired }
    db.myRates = db.myRates or { { s = 0, e = 0 }, { s = 0, e = 0 }, { s = 0, e = 0 } }
    db.pendingPosts = db.pendingPosts or {} -- [itemName] = { { id, d, t }, ... }
    return db
end

------------------------------------------------------------------------
-- Snapshots and diffs
------------------------------------------------------------------------
-- raw[itemID] = { {unit, count, owner}, ... } from the replicate scan
local function BuildSnapshot(raw)
    local items = {}
    for itemID, entries in pairs(raw) do
        local s = { min = math.huge, L = {}, o = {} }
        local ownersOK = true
        for _, e in ipairs(entries) do
            local u, q, owner = e[1], e[2], e[3]
            if u < s.min then s.min = u end
            s.L[u] = (s.L[u] or 0) + q
            if owner and owner ~= "" then
                local o = s.o[owner]
                if not o then o = { q = 0, m = u }; s.o[owner] = o end
                o.q = o.q + q
                if u < o.m then o.m = u end
            else
                ownersOK = false
            end
        end
        if not ownersOK then s.o = nil end
        items[itemID] = s
    end
    return items
end

local EMPTY = { min = math.huge, L = {}, o = {} }

local function DiffItem(prev, cur)
    local cheap = prev.min * CHEAP_BAND
    local bought = 0
    if prev.o and (cur.o or cur == EMPTY) then
        for owner, po in pairs(prev.o) do
            if po.m <= cheap then
                local co = cur.o[owner]
                local left = co and co.q or 0
                if po.q > left then bought = bought + (po.q - left) end
            end
        end
    else
        for u, q in pairs(prev.L) do
            if u <= cheap then
                local left = cur.L[u] or 0
                if q > left then bought = bought + (q - left) end
            end
        end
    end
    local undercut = (cur.min < prev.min) and 1 or 0
    return bought, undercut
end

function ns.Rates_OnFullScan(raw)
    local db = DB()
    local now = time()
    local cur = BuildSnapshot(raw)
    local prev = db.snap
    local learned = 0
    if prev and prev.items and prev.t then
        local gap = now - prev.t
        if gap >= MIN_GAP and gap <= MAX_GAP then
            local hours = gap / 3600
            for itemID, p in pairs(prev.items) do
                local bought, undercut = DiffItem(p, cur[itemID] or EMPTY)
                local r = db.rates[itemID]
                if not r then r = { u = 0, h = 0, x = 0, n = 0 }; db.rates[itemID] = r end
                r.u = r.u * DECAY + bought
                r.h = r.h * DECAY + hours
                r.x = r.x * DECAY + undercut
                r.n = r.n + 1
                r.t = now
                learned = learned + 1
            end
            ns.lastRateNote = ("Learned sell rates from a %d-minute scan gap (%d items)."):format(gap / 60, learned)
        elseif gap > MAX_GAP then
            ns.lastRateNote = "Last scan was over 6 hours ago, so no sell rates were learned this time. Scan again in 15+ minutes."
        end
    else
        ns.lastRateNote = "First scan saved. Scan again in 15+ minutes to start learning sell rates."
    end
    db.snap = { t = now, items = cur }
end

------------------------------------------------------------------------
-- The sell-chance model
------------------------------------------------------------------------
local function ExpectedShareSold(mu, q)
    if q <= 0 then return 1 end
    if mu <= 0 then return 0 end
    if q > 400 or mu > 3 * q + 30 then return math.min(1, mu / q) end
    local pmf = math.exp(-mu)
    local cdf, sum = pmf, 0
    for k = 0, q - 1 do
        sum = sum + (1 - cdf)          -- P(more than k buyers)
        pmf = pmf * mu / (k + 1)
        cdf = cdf + pmf
    end
    return sum / q
end

local function ModelChance(demand, under, T, qty)
    local front = T
    if under > 0 then front = (1 - math.exp(-under * T)) / under end
    -- once undercut you still catch some buyers after the cheaper stock runs out
    local effective = front + 0.3 * (T - front)
    return ExpectedShareSold(demand * effective, qty)
end

-- Your own sell-through per listing length, once you have enough results
function ns.BaseRates()
    local db = DB()
    local out = {}
    for d = 1, 3 do
        local m = db.myRates[d]
        local n = m.s + m.e
        if n >= 8 then
            out[d] = (m.s + 2 * ns.S.sellRate[d]) / (n + 2)
        else
            out[d] = ns.S.sellRate[d]
        end
    end
    return out
end

function ns.MarketStats(itemID)
    local r = DB().rates[itemID]
    if r and r.n >= 2 and r.h >= 0.5 then
        return r.u / r.h, r.x / r.h, r
    end
end

function ns.SellRates(itemID, qty)
    qty = math.max(1, qty or 1)
    local base = ns.BaseRates()
    local demand, under, r = ns.MarketStats(itemID)
    local own = DB().outcomes[itemID]
    local ownN = own and (own.s + own.e) or 0
    local info = { demand = demand, under = under, pairs = r and r.n, hours = r and r.h,
        ownSold = own and own.s or 0, ownTotal = ownN }
    if demand and ownN > 0 then info.source = "market + your sales"
    elseif demand then info.source = "market trend"
    elseif ownN > 0 then info.source = "your sales"
    else info.source = "default" end

    local out = {}
    for d = 1, 3 do
        local p = base[d]
        if demand then p = ModelChance(demand, under, HOURS[d], qty) end
        if ownN > 0 then
            local k = demand and OWN_WEIGHT or 2
            p = (own.s + k * p) / (ownN + k)
        end
        out[d] = math.max(0.03, math.min(0.98, p))
    end
    return out, info
end

function ns.RatesSummary()
    local db = DB()
    local learned = 0
    for _, r in pairs(db.rates) do if r.n >= 2 and r.h >= 0.5 then learned = learned + 1 end end
    local s, e = 0, 0
    for d = 1, 3 do s = s + db.myRates[d].s; e = e + db.myRates[d].e end
    return learned, s, e
end

------------------------------------------------------------------------
-- Your own auction results
------------------------------------------------------------------------
local function ToPattern(fmt)
    if not fmt then return nil end
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%s", "(.+)")
    return "^" .. p .. "$"
end

function ns.Rates_RecordPost(it, r)
    local db = DB()
    local name = C_Item.GetItemInfo(it.itemID)
    if not name or not r then return end
    local list = db.pendingPosts[name]
    if not list then list = {}; db.pendingPosts[name] = list end
    table.insert(list, { id = it.itemID, d = r.duration, t = time() })
    -- forget posts older than 3 days
    while list[1] and time() - list[1].t > 3 * 86400 do table.remove(list, 1) end
end

local function Resolve(name, sold)
    local db = DB()
    name = name and name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h%[?(.-)%]?|h", "%1")
    local list = name and db.pendingPosts[name]
    if not list or #list == 0 then return end
    local post = table.remove(list, 1) -- first result decides; later partial-sale messages are ignored
    local o = db.outcomes[post.id]
    if not o then o = { s = 0, e = 0 }; db.outcomes[post.id] = o end
    local m = db.myRates[post.d or 2]
    if sold then o.s = o.s + 1; m.s = m.s + 1 else o.e = o.e + 1; m.e = m.e + 1 end
end

local soldPat, expiredPat
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("CHAT_MSG_SYSTEM")
ev:SetScript("OnEvent", function(_, event, msg)
    if event == "PLAYER_LOGIN" then
        soldPat = ToPattern(ERR_AUCTION_SOLD_S)
        expiredPat = ToPattern(ERR_AUCTION_EXPIRED_S)
        return
    end
    if not ns.db or type(msg) ~= "string" then return end
    local ok, err = pcall(function()
        local name = soldPat and msg:match(soldPat)
        if name then return Resolve(name, true) end
        name = expiredPat and msg:match(expiredPat)
        if name then return Resolve(name, false) end
    end)
end)

------------------------------------------------------------------------
-- Helpers for the profit finder
------------------------------------------------------------------------
-- Units you could expect to sell within T hours as the cheapest listing (nil = unknown)
function ns.SellableUnits(itemID, T)
    local demand, under = ns.MarketStats(itemID)
    if not demand then return nil end
    local front = T
    if under > 0 then front = (1 - math.exp(-under * T)) / under end
    return demand * (front + 0.3 * (T - front))
end

-- Best way to relist qty units at unit price: picks the listing length with
-- the highest expected take-home after the cut and expected deposit losses
function ns.BestListing(itemID, qty, unit)
    local S = ns.S
    local rates, info = ns.SellRates(itemID, qty)
    local net = math.floor(unit * qty * (1 - S.ahCut))
    local best
    for d = 1, 3 do
        local ok, dep = pcall(C_AuctionHouse.CalculateCommodityDeposit, itemID, d, qty)
        local estimated = not (ok and dep)
        if estimated then dep = S.fallbackDeposit end
        local p = rates[d]
        local ev = net - dep * (1 - p) / p
        if not best or ev > best.ev then
            best = { ev = ev, d = d, dep = dep, p = p, estimated = estimated }
        end
    end
    best.net, best.info = net, info
    return best
end
