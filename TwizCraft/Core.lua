-- TwizCraft core: settings, item counts, prices and skill-up odds.
local ADDON, NS = ...
TwizCraft = NS

NS.DEFAULTS = {
    shown   = true,
    confirmOver = 50000, -- ask before spending more than 5g at a vendor in one go
    resellAH = false,   -- count AH resale of what you craft (default: vendor value only)
    steps   = 12,       -- steps shown
    partyShare = true,  -- share professions, recipes and crafting materials with party members running TwizCraft
    chars   = {},
    odds    = { yellow = { p = 0, a = 0 }, green = { p = 0, a = 0 } }, -- learned skill-up odds
}

function NS.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffb040TwizCraft:|r " .. msg)
end

function NS.safe(v)
    if v == nil then return nil end
    if issecretvalue then
        local ok, s = pcall(issecretvalue, v)
        if ok and s then return nil end
    end
    return v
end

function NS.CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

function NS.Char()
    local k = NS.CharKey()
    NS.db.chars[k] = NS.db.chars[k] or { profs = {} }
    return NS.db.chars[k]
end

function NS.Money(c)
    c = math.floor((c or 0) + 0.5)
    local neg = c < 0
    c = math.abs(c)
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local t
    if g > 0 then t = ("%dg %02ds"):format(g, s)
    elseif s > 0 then t = ("%ds %02dc"):format(s, cp)
    else t = cp .. "c" end
    return (neg and "-" or "") .. t
end

function NS.FormatTime(sec)
    sec = math.floor(sec + 0.5)
    if sec < 60 then return sec .. "s" end
    if sec < 3600 then return math.floor(sec / 60) .. "m" end
    return ("%dh %dm"):format(sec / 3600, (sec % 3600) / 60)
end

function NS.ItemName(id)
    local name = C_Item.GetItemInfo(id)
    if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return name or ("item " .. id)
end

function NS.ItemLink(id)
    local _, link = C_Item.GetItemInfo(id)
    return link or NS.ItemName(id)
end

------------------------------------------------------------------------
-- What you own: bags + bank (TwizQuest remembers the bank; so do we)
------------------------------------------------------------------------
function NS.BagCount(id)
    local ok, n = pcall(C_Item.GetItemCount, id)
    return ok and n or 0
end

function NS.BankCount(id)
    if TwizQuest and TwizQuest.BankCount then
        local ok, n = pcall(TwizQuest.BankCount, id)
        if ok and n then return n end
    end
    local okA, all = pcall(C_Item.GetItemCount, id, true)
    local okB, bags = pcall(C_Item.GetItemCount, id, false)
    if okA and okB and all and bags then return math.max(0, all - bags) end
    return 0
end

function NS.Owned(id)
    return NS.BagCount(id) + NS.BankCount(id) + (NS.MailCount and NS.MailCount(id) or 0)
end

-- a recipe slot may accept several items (e.g. any of a few fish): count them all
function NS.SlotBags(g)
    if not g.alts then return NS.BagCount(g.id) end
    local n = 0
    for _, id in ipairs(g.alts) do n = n + NS.BagCount(id) end
    return n
end
function NS.SlotOwned(g)
    if not g.alts then return NS.Owned(g.id) end
    local n = 0
    for _, id in ipairs(g.alts) do n = n + NS.Owned(id) end
    return n
end

-- the profession you picked may use a different id than its window reports
function NS.ResolveLine(line, name)
    local c = NS.Char()
    if line and c.profs[line] then return line end
    for k, p in pairs(c.profs) do
        if p.name == name then return k end
    end
    return line
end

------------------------------------------------------------------------
-- Prices. Each reagent can come from a vendor, the AH, or your own crafting.
------------------------------------------------------------------------
function NS.VendorSell(id)
    return select(11, C_Item.GetItemInfo(id)) or 0
end

-- Price a merchant charges, if any merchant we've seen sells it
function NS.VendorBuy(id)
    local m = NS.db.merchant and NS.db.merchant[id]
    if m then return m.cost, m.npc, m.zone end
    local dw = DepositWiseDB and DepositWiseDB.merchant and DepositWiseDB.merchant[id]
    if dw then return dw.cost, dw.npc, dw.zone end
    -- not seen yet, but Questie says a friendly vendor sells it: estimate
    if NS.QuestieVendorPrice then
        local ok, p = pcall(NS.QuestieVendorPrice, id)
        if ok and p then return p, nil, nil, true end
    end
end

-- Lowest AH price TwizAH knows
function NS.AHPrice(id)
    if TwizAH and TwizAH.KnownPrice then
        local ok, p, t = pcall(TwizAH.KnownPrice, id)
        if ok and p then return p, t end
    end
end

-- What a crafted item sells back for
function NS.Resale(id, n)
    local v = NS.VendorSell(id) * n
    if NS.db.resellAH then
        local p = NS.AHPrice(id)
        if p then v = math.max(v, math.floor(p * 0.95) * n) end
    end
    return v
end

-- Remember merchant prices ourselves too
local function ScanMerchant()
    NS.db.merchant = NS.db.merchant or {}
    local npc, zone = UnitName("npc"), GetZoneText()
    for i = 1, (GetMerchantNumItems() or 0) do
        local id = GetMerchantItemID and GetMerchantItemID(i)
        local price, stack, ext
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local info = C_MerchantFrame.GetItemInfo(i)
            if info then price, stack, ext = info.price, info.stackCount, info.hasExtendedCost end
        else
            local _, _, p, q, _, _, _, e = GetMerchantItemInfo(i)
            price, stack, ext = p, q, e
        end
        if id and price and price > 0 and not ext then
            NS.db.merchant[id] = { cost = price / math.max(1, stack or 1), npc = npc, zone = zone, t = time() }
        end
    end
end

------------------------------------------------------------------------
-- Skill-up odds (classic): orange always; from yellow it falls to 0 at gray:
--   chance = (gray - skill) / (gray - yellow)
-- then nudged by what we've seen you actually get.
------------------------------------------------------------------------
function NS.Color(r, s)
    if s >= r.gray then return "gray" end
    if s >= r.green then return "green" end
    if s >= r.yellow then return "yellow" end
    return "orange"
end

local function Factor(zone)
    local o = NS.db.odds[zone]
    if not o then return 1 end
    return math.max(0.5, math.min(1.5, (o.a + 5) / (o.p + 5)))
end

function NS.Chance(r, s)
    if s >= r.gray then return 0 end
    if s < r.yellow then return 1 end
    local c = (r.gray - s) / math.max(1, r.gray - r.yellow)
    c = c * Factor(NS.Color(r, s))
    return math.max(0.02, math.min(1, c))
end

function NS.RecordOdds(zone, predicted, got)
    local o = NS.db.odds[zone]
    if not o then return end
    o.p, o.a = o.p + predicted, o.a + (got and 1 or 0)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("MERCHANT_SHOW")
f:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg == ADDON then
        CraftRouteDB = CraftRouteDB or {}
        for k, v in pairs(NS.DEFAULTS) do
            if CraftRouteDB[k] == nil then
                if type(v) == "table" then
                    CraftRouteDB[k] = {}
                    for k2, v2 in pairs(v) do
                        if type(v2) == "table" then
                            CraftRouteDB[k][k2] = {}
                            for k3, v3 in pairs(v2) do CraftRouteDB[k][k2][k3] = v3 end
                        else CraftRouteDB[k][k2] = v2 end
                    end
                else CraftRouteDB[k] = v end
            end
        end
        NS.db = CraftRouteDB
    elseif event == "MERCHANT_SHOW" and NS.db then
        C_Timer.After(0.3, function() pcall(ScanMerchant) end)
    end
end)
