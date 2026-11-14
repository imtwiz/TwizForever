-- TwizCraft mailbox: AH purchases (and anything else mailed to you) wait in
-- the mailbox. They count toward your shopping list right away, and the route
-- gets a "Mailbox: pick up" stop until you collect them.
--   * after a purchase: the amount you bought is added at once
--   * whenever the mailbox is open: the real inbox replaces our guess
--   * if a purchase lands straight in your bags instead, it isn't double counted
local ADDON, NS = ...

local function Store()
    local c = NS.Char()
    c.mail = c.mail or { items = {}, at = 0 }
    return c.mail
end

function NS.MailCount(id)
    if not NS.db then return 0 end
    local s = Store()
    return s.items[id] or 0
end

-- You just bought qty of id on the AH: it's on its way to the mailbox.
function NS.NoteMailed(id, qty)
    if not (NS.db and id and qty and qty > 0) then return end
    local s = Store()
    local before = NS.BagCount(id)
    s.items[id] = (s.items[id] or 0) + qty
    -- some purchases arrive straight in your bags; then they aren't in the mail
    C_Timer.After(3, function()
        if NS.BagCount(id) - before >= qty and (s.items[id] or 0) >= qty then
            s.items[id] = s.items[id] - qty
            if s.items[id] <= 0 then s.items[id] = nil end
            if NS.Replan then NS.Replan(true) end
        end
    end)
end

------------------------------------------------------------------------
-- Reading the real inbox
------------------------------------------------------------------------
local function ScanInbox()
    if not (NS.db and MailFrame and MailFrame:IsShown()) then return end
    local shown, total = GetInboxNumItems()
    if not shown then return end
    local items = {}
    for i = 1, shown do
        for a = 1, (ATTACHMENTS_MAX_RECEIVE or 12) do
            local _, itemID, _, count = GetInboxItem(i, a)
            if itemID then items[itemID] = (items[itemID] or 0) + (count or 1) end
        end
    end
    local s = Store()
    -- if the inbox holds more mail than it shows, keep our counts for the rest
    if (total or shown) > shown then
        for id, n in pairs(items) do s.items[id] = math.max(n, s.items[id] or 0) end
    else
        s.items = items
    end
    s.at = time()
    if NS.Replan then NS.Replan(true) end
end

-- where your mailboxes are (for the route)
local function RememberSpot()
    local R = TwizQuest
    if not (R and R.Bridge and R.Bridge() and R.PlayerPos) then return end
    local x, y, inst = R.PlayerPos()
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if not (x and pos) then return end
    local mx, my = pos:GetXY()
    NS.db.mailSpots = NS.db.mailSpots or {}
    local list = NS.db.mailSpots[inst] or {}
    for _, sp in ipairs(list) do
        if NS.Dist2(sp.x, sp.y, x, y) < 40 then return end
    end
    table.insert(list, { x = x, y = y, map = map, mx = mx * 100, my = my * 100 })
    NS.db.mailSpots[inst] = list
end

function NS.NearestMailbox(inst, px, py)
    local best, bd
    for _, sp in ipairs(NS.db.mailSpots and inst and NS.db.mailSpots[inst] or {}) do
        local d = NS.Dist2(px, py, sp.x, sp.y)
        if not bd or d < bd then best, bd = sp, d end
    end
    return best
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED" }) do pcall(f.RegisterEvent, f, e) end
local pending
f:SetScript("OnEvent", function(_, event)
    if not NS.db then return end
    if event == "MAIL_SHOW" then
        pcall(RememberSpot)
        if CheckInbox then CheckInbox() end
    end
    if event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
        if not pending then
            pending = true
            C_Timer.After(0.4, function() pending = false; ScanInbox() end)
        end
    elseif event == "MAIL_CLOSED" then
        ScanInbox()
    end
end)
