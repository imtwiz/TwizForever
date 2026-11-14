-- TwizAH: Mail - learns what actually sold/expired from Auction House mail,
-- and a "Collect AH Mail" button that takes the gold and returned items from AH
-- mail only (never touches mail from players, never pays COD).
local ADDON, ns = ...

local function Pattern(fmt)
    if not fmt then return nil end
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%s", "(.+)")
    return "^" .. p .. "$"
end

local PAT = {}
local function BuildPatterns()
    PAT.sold      = Pattern(AUCTION_SOLD_MAIL_SUBJECT or "Auction successful: %s")
    PAT.expired   = Pattern(AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s")
    PAT.cancelled = Pattern(AUCTION_REMOVED_MAIL_SUBJECT or "Auction cancelled: %s")
    PAT.won       = Pattern(AUCTION_WON_MAIL_SUBJECT or "Auction won: %s")
    PAT.outbid    = Pattern(AUCTION_OUTBID_MAIL_SUBJECT or "Outbid on %s")
end

-- What kind of AH mail is this? returns kind, itemName  (nil if not AH mail)
local function Classify(i)
    local _, _, sender, subject, money, cod, _, itemCount = GetInboxHeaderInfo(i)
    if not subject then return nil end
    for _, kind in ipairs({ "sold", "expired", "cancelled", "won", "outbid" }) do
        local p = PAT[kind]
        local name = p and subject:match(p)
        if name then return kind, name, money or 0, itemCount or 0, cod or 0 end
    end
    local invoiceType, itemName = GetInboxInvoiceInfo and GetInboxInvoiceInfo(i)
    if invoiceType == "seller" then return "sold", itemName, money or 0, itemCount or 0, cod or 0 end
    if invoiceType == "buyer" then return "won", itemName, money or 0, itemCount or 0, cod or 0 end
end

------------------------------------------------------------------------
-- Learning from the inbox (each AH mail counted once)
------------------------------------------------------------------------
local function Seen()
    ns.db.mailSeen = ns.db.mailSeen or {} -- [signature] = count currently accounted for
    return ns.db.mailSeen
end

function ns.ScanInbox()
    if not ns.db then return end
    local shown, total = GetInboxNumItems()
    shown = shown or 0
    local occ, info = {}, {}
    for i = 1, shown do
        local kind, name, money, items = Classify(i)
        if kind == "sold" or kind == "expired" or kind == "cancelled" then
            local _, _, _, subject = GetInboxHeaderInfo(i)
            local _, _, _, bid, buyout = GetInboxInvoiceInfo and GetInboxInvoiceInfo(i)
            -- money disappears once taken, so it isn't part of the signature
            local sig = kind .. "|" .. (subject or "") .. "|" .. tostring(buyout or bid or "")
            occ[sig] = (occ[sig] or 0) + 1
            info[sig] = { kind = kind, name = name }
        end
    end
    local seen = Seen()
    local new = 0
    for sig, n in pairs(occ) do
        local before = seen[sig] or 0
        for _ = 1, n - before do
            local x = info[sig]
            -- already counted from the chat message while you were online?
            if not (ns.ConsumeChatOutcome and ns.ConsumeChatOutcome(x.name, x.kind)) then
                ns.RecordOutcome(x.name, x.kind)
            end
            new = new + 1
        end
        seen[sig] = n
    end
    -- mail that's gone (collected) no longer needs remembering - only when we saw the whole inbox
    if (total or shown) <= shown then
        for sig in pairs(seen) do if not occ[sig] then seen[sig] = nil end end
    end
    if new > 0 and ns.UI then ns.UI.Refresh() end
    return new
end

------------------------------------------------------------------------
-- Collect AH Mail
------------------------------------------------------------------------
local collecting, collected, collectedItems
local waitToken

local function FreeSlots()
    if not C_Container.GetContainerNumFreeSlots then return 99 end
    local n = 0
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4) do
        if C_Container.GetContainerNumFreeSlots then
            n = n + (C_Container.GetContainerNumFreeSlots(bag) or 0)
        end
    end
    return n
end

function ns.AHMailSummary()
    local count, gold, items = 0, 0, 0
    local shown = GetInboxNumItems() or 0
    for i = 1, shown do
        local kind, _, money, itemCount, cod = Classify(i)
        if kind and (cod or 0) == 0 and ((money or 0) > 0 or (itemCount or 0) > 0) then
            count = count + 1; gold = gold + (money or 0); items = items + (itemCount or 0)
        end
    end
    return count, gold, items
end

local function StopCollecting(msg)
    if not collecting then return end
    collecting = false
    waitToken = nil
    ns.Print(("Collected %s%s from AH mail.%s"):format(ns.Money(collected),
        collectedItems > 0 and (" and %d item stack%s"):format(collectedItems, collectedItems == 1 and "" or "s") or "",
        msg and (" " .. msg) or ""))
    if ns.Mail_UpdateButton then ns.Mail_UpdateButton() end
end

local function CollectNext()
    if not collecting then return end
    if not (MailFrame and MailFrame:IsShown()) then return StopCollecting("Mailbox closed.") end
    local shown = GetInboxNumItems() or 0
    for i = shown, 1, -1 do
        local kind, _, money, itemCount, cod = Classify(i)
        if kind and (cod or 0) == 0 then
            if (money or 0) > 0 then
                local token = {}
                waitToken = token
                collected = collected + money
                TakeInboxMoney(i)
                C_Timer.After(1.5, function() if waitToken == token then waitToken = nil; CollectNext() end end)
                return
            elseif (itemCount or 0) > 0 then
                if FreeSlots() <= 0 then return StopCollecting("Your bags are full.") end
                local token = {}
                waitToken = token
                collectedItems = collectedItems + 1
                AutoLootMailItem(i)
                C_Timer.After(1.5, function() if waitToken == token then waitToken = nil; CollectNext() end end)
                return
            end
        end
    end
    StopCollecting()
end

function ns.CollectAHMail()
    if collecting then return end
    if not (MailFrame and MailFrame:IsShown()) then ns.Print("Open your mailbox first."); return end
    pcall(ns.ScanInbox) -- record outcomes before the mail disappears
    collecting, collected, collectedItems = true, 0, 0
    CollectNext()
end

------------------------------------------------------------------------
-- Button on the mailbox
------------------------------------------------------------------------
local button
function ns.Mail_UpdateButton()
    if not button then return end
    local n, gold, items = ns.AHMailSummary()
    if collecting then
        button:SetText("Collecting...")
        button:SetEnabled(false)
    else
        button:SetText(("Collect AH Mail (%d)"):format(n))
        button:SetEnabled(n > 0)
    end
    button.gold, button.items = gold, items
end

local function MakeButton()
    if button or not MailFrame then return end
    button = CreateFrame("Button", nil, MailFrame, "UIPanelButtonTemplate")
    button:SetSize(170, 22)
    button:SetPoint("TOPRIGHT", MailFrame, "BOTTOMRIGHT", 0, -2)
    button:SetScript("OnClick", function() ns.CollectAHMail() end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("TwizAH: Collect AH Mail")
        GameTooltip:AddLine("Takes the gold from sold auctions and the items from expired or cancelled ones. Mail from players is never touched, and COD mail is skipped.", 1, 1, 1, true)
        GameTooltip:AddDoubleLine("Gold waiting", ns.Money(self.gold or 0), 1, 1, 1)
        GameTooltip:AddDoubleLine("Item stacks waiting", tostring(self.items or 0), 1, 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED", "UI_ERROR_MESSAGE" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local scanPending
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "PLAYER_LOGIN" then
        BuildPatterns()
    elseif event == "MAIL_SHOW" then
        MakeButton()
        if CheckInbox then CheckInbox() end
        ns.Mail_UpdateButton()
    elseif event == "MAIL_INBOX_UPDATE" then
        if not scanPending then
            scanPending = true
            C_Timer.After(0.3, function()
                scanPending = false
                pcall(ns.ScanInbox)
                ns.Mail_UpdateButton()
            end)
        end
        if collecting and waitToken then
            waitToken = nil
            C_Timer.After(0.35, CollectNext) -- give the server a moment between takes
        end
    elseif event == "MAIL_CLOSED" then
        if collecting then StopCollecting() end
    elseif event == "UI_ERROR_MESSAGE" then
        local msg = a2 or a1
        if collecting and type(msg) == "string" and ERR_INV_FULL and msg == ERR_INV_FULL then
            StopCollecting("Your bags are full.")
        end
    end
end)
