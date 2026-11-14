-- TwizAH: Rates - learns how fast things actually sell
--
-- Two sources, blended per item:
--  1) Market trend: every full scan is compared to the previous one. Units
--     that vanished from near the cheapest price = units bought (expiring
--     listings and probable reposts are left out, see below). Also counted:
--     how often someone lists below the cheapest price (undercut frequency).
--  2) Your own results: AH mail (sold / expired), your owned-auctions list,
--     and the "A buyer has been found..." chat message.
--
-- Sell chance for a listing of q units lasting T hours:
--   time you stay cheapest  ~ (1 - e^(-uT)) / u   (u = undercuts per hour)
--   expected buyers         ~ Poisson(demand/hour x that time)
--   chance                  = expected share of your q units that sell
local ADDON, ns = ...

local HOURS = ns.DURATION_HOURS or { 2, 8, 24 }
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
--
-- Forever's full scan doesn't name sellers, so a sale can't be told apart
-- from a listing that expired or was cancelled and reposted. To stay honest:
--  * every listing carries its time-left band; listings that could have
--    expired between the two scans don't count as sales when they vanish
--  * new listings that appear below the old cheapest price are treated as
--    probable reposts and half their amount is taken off the "bought" count
-- That under-counts a little, which is the safe direction: deposits are only
-- risked on items that really sell.
--
-- A snapshot is stored per item as one compact string:
--   "min|unit,qty,short,medium,long;unit,qty,short,medium,long;..."
------------------------------------------------------------------------
local BAND_MAX_HOURS = { [0] = 0.5, [1] = 2, [2] = 12, [3] = 48 } -- longest time left in each band

-- raw[itemID] = { {unit, count, owner, timeLeftBand}, ... }
-- Returns the full snapshot (used now, in memory) and a trimmed one to save:
-- the next comparison only looks at listings within CHEAP_BAND of the cheapest.
local function BuildSnapshot(raw)
    local items, saved = {}, {}
    for itemID, entries in pairs(raw) do
        local levels, min = {}, math.huge
        for _, e in ipairs(entries) do
            local u, q, band = e[1], e[2], e[4]
            if u < min then min = u end
            local l = levels[u]
            if not l then l = { u, 0, 0, 0, 0 }; levels[u] = l end
            l[2] = l[2] + q
            if band == 0 then l[3] = l[3] + q elseif band == 1 then l[4] = l[4] + q elseif band == 2 then l[5] = l[5] + q end
        end
        local parts, cheapParts = {}, {}
        local limit = min * CHEAP_BAND
        for u, l in pairs(levels) do
            local s = table.concat(l, ",")
            parts[#parts + 1] = s
            if u <= limit then cheapParts[#cheapParts + 1] = s end
        end
        items[itemID] = min .. "|" .. table.concat(parts, ";")
        saved[itemID] = min .. "|" .. table.concat(cheapParts, ";")
    end
    return items, saved
end

-- returns min, { [unit] = { qty, short, medium, long } }
local function ParseSnap(v)
    if type(v) == "table" then -- older format: { min, L = { [unit] = qty } }
        local L = {}
        for u, q in pairs(v.L or {}) do L[u] = { q, 0, 0, 0 } end
        return v.min or math.huge, L
    end
    local min, rest = v:match("^([^|]*)|(.*)$")
    local L = {}
    for u, q, s, m, l in (rest or ""):gmatch("([%d%.]+),(%d+),(%d+),(%d+),(%d+)") do
        L[tonumber(u)] = { tonumber(q), tonumber(s), tonumber(m), tonumber(l) }
    end
    return tonumber(min) or math.huge, L
end

local function DiffItem(prevV, curV, gapHours)
    local pmin, pL = ParseSnap(prevV)
    local cmin, cL = math.huge, {}
    if curV then cmin, cL = ParseSnap(curV) end
    local cheap = pmin * CHEAP_BAND
    local bought = 0
    for u, p in pairs(pL) do
        if u <= cheap then
            local left = cL[u] and cL[u][1] or 0
            local gone = p[1] - left
            if gone > 0 then
                -- listings whose time could have run out since the last scan may simply have expired
                local couldExpire = p[2]
                if gapHours >= BAND_MAX_HOURS[1] then couldExpire = couldExpire + p[3] end
                if gapHours >= BAND_MAX_HOURS[2] then couldExpire = couldExpire + p[4] end
                bought = bought + math.max(0, gone - couldExpire)
            end
        end
    end
    -- new listings below the old cheapest: probably reposts of cancelled ones
    local newBelow = 0
    for u, c in pairs(cL) do if u < pmin then newBelow = newBelow + c[1] end end
    bought = math.max(0, bought - 0.5 * newBelow)
    local undercut = (cmin < pmin) and 1 or 0
    return bought, undercut
end

function ns.Rates_OnFullScan(raw)
    local db = DB()
    local now = time()
    local cur, toSave = BuildSnapshot(raw)
    local prev = db.snap
    local learned = 0
    if prev and prev.items and prev.t then
        local gap = now - prev.t
        if gap >= MIN_GAP and gap <= MAX_GAP then
            local hours = gap / 3600
            for itemID, p in pairs(prev.items) do
                local ok, bought, undercut = pcall(DiffItem, p, cur[itemID], hours)
                if ok then
                    local r = db.rates[itemID]
                    if not r then r = { u = 0, h = 0, x = 0, n = 0 }; db.rates[itemID] = r end
                    r.u = r.u * DECAY + bought
                    r.h = r.h * DECAY + hours
                    r.x = r.x * DECAY + undercut
                    r.n = r.n + 1
                    r.t = now
                    learned = learned + 1
                end
            end
            ns.lastRateNote = ("Learned sell rates from a %d-minute scan gap (%d items)."):format(gap / 60, learned)
        elseif gap > MAX_GAP then
            ns.lastRateNote = "Last scan was over 6 hours ago, so no sell rates were learned this time. Scan again in 15+ minutes."
        end
    else
        ns.lastRateNote = "First scan saved. Scan again in 15+ minutes to start learning sell rates."
    end
    db.snap = { t = now, items = toSave }
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
    if type(r) == "table" and (r.n or 0) >= 2 and (r.h or 0) >= 0.5 then
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

local function CleanName(name)
    if not name then return nil end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h%[?(.-)%]?|h", "%1")
    name = name:gsub("%s*%(%d+%)%s*$", "") -- "Linen Cloth (20)" -> "Linen Cloth"
    return name
end

-- itemID for a name we've seen (pending posts, saved names, bags)
local function IDForName(name)
    local db = DB()
    local list = db.pendingPosts[name]
    if list and list[1] then return list[1].id end
    for id, n in pairs(db.names or {}) do if n == name then return id end end
end

-- kind = "sold" | "expired" | "cancelled". Each posted auction is resolved once (first result wins).
function ns.RecordOutcome(name, kind)
    local db = DB()
    name = CleanName(name)
    if not name then return end
    local list = db.pendingPosts[name]
    local post = list and table.remove(list, 1)
    if list and #list == 0 then db.pendingPosts[name] = nil end
    if kind == "cancelled" then return end
    local id = post and post.id or IDForName(name)
    if not id then return end
    local o = db.outcomes[id]
    if not o then o = { s = 0, e = 0 }; db.outcomes[id] = o end
    if kind == "sold" then o.s = o.s + 1 else o.e = o.e + 1 end
    if post then
        local m = db.myRates[post.d or 2]
        if m then if kind == "sold" then m.s = m.s + 1 else m.e = m.e + 1 end end
    end
    ns.outcomeChanged = true
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
    pcall(function()
        -- chat messages only mark the mail we'll see later as already counted
        local name = soldPat and msg:match(soldPat)
        if name then ns.MarkChatOutcome(name, "sold"); return end
        name = expiredPat and msg:match(expiredPat)
        if name then ns.MarkChatOutcome(name, "expired") end
    end)
end)

-- The same sale shows up as a chat message (if you're online) and later as a
-- mail. Count it once: chat counts immediately; the matching mail is skipped.
-- (saved, so a sale seen in chat today isn't counted again from tomorrow's mail)
local function ChatCounted()
    local db = DB()
    db.chatCounted = db.chatCounted or {} -- [kind:name] = { time, time, ... }
    return db.chatCounted
end
function ns.MarkChatOutcome(name, kind)
    name = CleanName(name)
    if not name then return end
    ns.RecordOutcome(name, kind)
    local c = ChatCounted()
    local key = kind .. ":" .. name
    c[key] = c[key] or {}
    table.insert(c[key], time())
end
function ns.ConsumeChatOutcome(name, kind)
    local c = ChatCounted()
    local key = kind .. ":" .. (CleanName(name) or "")
    local list = c[key]
    -- forget chat notes older than 3 days (AH mail lasts 30 days, but sale mail arrives within an hour)
    while list and list[1] and time() - list[1] > 3 * 86400 do table.remove(list, 1) end
    if list and list[1] then
        table.remove(list, 1)
        if #list == 0 then c[key] = nil end
        return true
    end
end

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
        local score = ev - (1 / p - 1) * (ns.RelistEffort and ns.RelistEffort(net) or 0)
        if not best or score > best.score then
            best = { ev = ev, d = d, dep = dep, p = p, estimated = estimated, score = score }
        end
    end
    best.net, best.info = net, info
    return best
end
