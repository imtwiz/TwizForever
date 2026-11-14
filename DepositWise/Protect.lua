-- DepositWise: Protect - things auto-vendor must never sell, even when a vendor
-- pays more than the AH:
--   * anything you bought (vendor or AH) in the last 2 hours - you bought it for a reason
--   * materials your profitable crafts need (Craft tab: Craft / Buy & craft)
--   * CraftRoute's current leveling plan (what you have and what you're buying)
--   * AutoChef's recipe ingredients
-- (Quest items, profession tools and /dw exclude are handled elsewhere and still apply.)
local ADDON, ns = ...

local RECENT_SECONDS = 2 * 3600

local function Recent()
    ns.db.recentBuys = ns.db.recentBuys or {} -- [itemID] = time
    return ns.db.recentBuys
end

function ns.NoteBought(itemID)
    if itemID then Recent()[itemID] = time() end
end

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- Built fresh for each merchant visit (cheap enough, and always current)
function ns.ProtectedSet()
    local set = {}
    local now = time()
    for id, t in pairs(Recent()) do
        if now - t <= RECENT_SECONDS then set[id] = "bought recently" else Recent()[id] = nil end
    end
    -- profitable crafts on the Craft tab
    if ns.SupplyNeeds then
        local ok, needs = pcall(ns.SupplyNeeds)
        for _, e in ipairs(ok and needs or {}) do set[e.itemID] = set[e.itemID] or "needed for a profitable craft" end
    end
    -- CraftRoute leveling plan
    local plan = CraftRoute and CraftRoute.currentPlan
    for _, e in ipairs(plan and plan.shop or {}) do
        if e.id then set[e.id] = set[e.id] or "in your CraftRoute plan" end
    end
    -- AutoChef recipes
    local ac = AutoChefDB and AutoChefDB.chars
    local char = ac and (ac[CharKey()] or nil)
    if not char and ac then
        -- AutoChef keys characters as "Name-Realm"; fall back to any character with your name
        local me = UnitName("player") or "?"
        for k, v in pairs(ac) do if k:sub(1, #me + 1) == me .. "-" then char = v; break end end
    end
    for _, r in pairs(char and char.recipes or {}) do
        for _, slot in ipairs(r.reagents or {}) do
            for _, id in ipairs(slot.ids or {}) do set[id] = set[id] or "an AutoChef ingredient" end
            if slot.id then set[slot.id] = set[slot.id] or "an AutoChef ingredient" end
        end
    end
    return set
end

------------------------------------------------------------------------
-- Watch purchases
------------------------------------------------------------------------
if BuyMerchantItem and hooksecurefunc then
    hooksecurefunc("BuyMerchantItem", function(index)
        local id = GetMerchantItemID and GetMerchantItemID(index)
        if id and ns.db then ns.NoteBought(id) end
    end)
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "COMMODITY_PURCHASE_SUCCEEDED")
ev:SetScript("OnEvent", function()
    if not ns.db then return end
    -- whoever was buying: DepositWise's supplies or CraftRoute's shopping
    if ns.buy and ns.buy.itemID then ns.NoteBought(ns.buy.itemID) end
    local cr = CraftRoute and CraftRoute.ah
    if cr and cr.item and cr.item.id then ns.NoteBought(cr.item.id) end
end)
