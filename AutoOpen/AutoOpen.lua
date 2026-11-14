-- AutoOpen: opens chests, boxes, gifts, clams, shells and other openable
-- containers in your bags, one at a time, only when it's safe to do so.

local ADDON = ...
local f = CreateFrame("Frame")

local DEFAULTS = {
    enabled  = true,
    announce = true,   -- print "Opened [item]" in chat
    minFree  = 1,      -- free bag slots required before opening anything
    ignore   = {},     -- [itemID] = true, never open these
}

local db
local busy             -- the open we're waiting on
local pending          -- a Step() is already scheduled
local skipSession = {} -- [itemID] = true after it failed to open twice
local failures = {}    -- [itemID] = count
local lootOpen = false
local windows = {}     -- vendor/bank/mail/etc windows currently open
local fullWarned = false

local OPEN_GAP   = 0.35 -- seconds between opens
local LOOT_WAIT  = 1.0  -- how long to wait for the loot window to appear
local BUSY_LIMIT = 6.0  -- give up waiting on one open after this long

------------------------------------------------------------------------
-- Helpers / API compatibility
------------------------------------------------------------------------
local C = C_Container

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffAutoOpen:|r " .. msg)
end

local function NumSlots(bag)
    if C and C.GetContainerNumSlots then return C.GetContainerNumSlots(bag) or 0 end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function FreeSlots(bag)
    if C and C.GetContainerNumFreeSlots then return C.GetContainerNumFreeSlots(bag) end
    if GetContainerNumFreeSlots then return GetContainerNumFreeSlots(bag) end
    return 0, 0
end

local function ItemInfo(bag, slot)
    if C and C.GetContainerItemInfo then
        local i = C.GetContainerItemInfo(bag, slot)
        if not i then return end
        return i.itemID, i.hasLoot, i.isLocked, i.stackCount, i.hyperlink
    end
    if GetContainerItemInfo then
        local _, count, locked, _, _, lootable, link, _, _, itemID = GetContainerItemInfo(bag, slot)
        return itemID, lootable, locked, count, link
    end
end

local function UseItem(bag, slot)
    if C and C.UseContainerItem then return C.UseContainerItem(bag, slot) end
    return UseContainerItem(bag, slot)
end

local function LastBag()
    return NUM_BAG_SLOTS or 4
end

local function TotalFree()
    local n = 0
    for bag = 0, LastBag() do
        local free, bagType = FreeSlots(bag)
        if (bagType or 0) == 0 then n = n + (free or 0) end
    end
    return n
end

-- Turn a format string like "Requires Level %d" into a Lua pattern.
local function ToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    fmt = fmt:gsub("%%%d?%$?[ds]", ".+")
    return "^" .. fmt .. "$"
end

local REQ_PATTERNS = {}
for _, g in ipairs({ "ITEM_MIN_LEVEL", "ITEM_REQ_SKILL", "ITEM_REQ_REPUTATION", "ITEM_MIN_SKILL" }) do
    local p = ToPattern(_G[g])
    if p then REQ_PATTERNS[#REQ_PATTERNS + 1] = p end
end
local OPENABLE_TEXT = ITEM_OPENABLE or "<Right Click to Open>"
local LOCKED_TEXT   = LOCKED or "Locked"

local function IsRed(r, g, b)
    return r and r > 0.9 and g and g < 0.3 and b and b < 0.3
end

-- Returns a list of { text, red } for an item's tooltip.
local scanTip
local function TooltipLines(bag, slot)
    local out = {}
    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local data = C_TooltipInfo.GetBagItem(bag, slot)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                if TooltipUtil and TooltipUtil.SurfaceArgs and not line.leftText then
                    TooltipUtil.SurfaceArgs(line)
                end
                local c = line.leftColor
                out[#out + 1] = { text = line.leftText, red = c and IsRed(c.r, c.g, c.b) }
            end
            return out
        end
    end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "AutoOpenScanTip", nil, "GameTooltipTemplate")
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    scanTip:ClearLines()
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:SetBagItem(bag, slot)
    for i = 1, scanTip:NumLines() do
        local fs = _G["AutoOpenScanTipTextLeft" .. i]
        if fs then
            out[#out + 1] = { text = fs:GetText(), red = IsRed(fs:GetTextColor()) }
        end
    end
    return out
end

-- Is this slot something we should open right now?
local function ShouldOpen(bag, slot)
    local itemID, hasLoot, isLocked = ItemInfo(bag, slot)
    if not itemID or isLocked then return false end
    if db.ignore[itemID] or skipSession[itemID] then return false end

    local lines = TooltipLines(bag, slot)
    local openable = hasLoot
    for _, l in ipairs(lines) do
        local t = l.text
        if t then
            if t == OPENABLE_TEXT then openable = true end
            if t == LOCKED_TEXT then return false end          -- unpicked lockbox
            if l.red then
                for _, p in ipairs(REQ_PATTERNS) do
                    if t:match(p) then return false end         -- can't use it yet
                end
            end
        end
    end
    return openable and true or false
end

------------------------------------------------------------------------
-- When is it NOT safe to open?
------------------------------------------------------------------------
local WINDOW_FRAMES = {
    "MerchantFrame", "BankFrame", "MailFrame", "TradeFrame",
    "AuctionHouseFrame", "AuctionFrame", "GuildBankFrame",
}

local function Blocked()
    if InCombatLockdown() or UnitAffectingCombat("player") then return "combat" end
    if UnitIsDeadOrGhost("player") then return "dead" end
    if lootOpen or (LootFrame and LootFrame:IsShown()) then return "loot" end
    if next(windows) then return "window" end
    for _, name in ipairs(WINDOW_FRAMES) do
        local fr = _G[name]
        if fr and fr.IsShown and fr:IsShown() then return "window" end
    end
    if GetCursorInfo() then return "cursor", true end
    if SpellIsTargeting and SpellIsTargeting() then return "targeting", true end
    if UnitCastingInfo and UnitCastingInfo("player") then return "casting", true end
    if UnitChannelInfo and UnitChannelInfo("player") then return "casting", true end
    return nil
end

------------------------------------------------------------------------
-- Main loop
------------------------------------------------------------------------
local Step

local function Schedule(delay)
    if pending then return end
    pending = true
    C_Timer.After(delay or 0.1, function()
        pending = false
        Step()
    end)
end

local function Finish()
    local b = busy
    if not b then return end
    busy = nil
    local itemID, _, _, count = ItemInfo(b.bag, b.slot)
    if itemID == b.itemID and (count or 1) >= (b.count or 1) then
        -- Nothing changed: it didn't open (level requirement, unique loot, etc.)
        failures[b.itemID] = (failures[b.itemID] or 0) + 1
        if failures[b.itemID] >= 2 then
            skipSession[b.itemID] = true
            Print("couldn't open " .. (b.link or ("item " .. b.itemID)) ..
                ", skipping it until you /reload.")
        end
    elseif db.announce then
        Print("opened " .. (b.link or ("item " .. b.itemID)))
    end
    Schedule(OPEN_GAP)
end

Step = function()
    if not db or not db.enabled or busy then return end

    local reason, transient = Blocked()
    if reason then
        if transient then Schedule(1.0) end
        return
    end

    if TotalFree() < db.minFree then
        if not fullWarned then
            for bag = 0, LastBag() do
                for slot = 1, NumSlots(bag) do
                    if ShouldOpen(bag, slot) then
                        fullWarned = true
                        Print("bags are full, waiting for space before opening anything.")
                        return
                    end
                end
            end
        end
        return
    end
    fullWarned = false

    for bag = 0, LastBag() do
        for slot = 1, NumSlots(bag) do
            if ShouldOpen(bag, slot) then
                local itemID, _, _, count, link = ItemInfo(bag, slot)
                busy = { bag = bag, slot = slot, itemID = itemID, count = count,
                         link = link, started = GetTime() }
                UseItem(bag, slot)
                local token = busy
                C_Timer.After(LOOT_WAIT, function()
                    if busy == token and not lootOpen then Finish() end
                end)
                C_Timer.After(BUSY_LIMIT, function()
                    if busy == token then Finish() end
                end)
                return
            end
        end
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local WINDOW_EVENTS = {
    MERCHANT_SHOW = "merchant",        MERCHANT_CLOSED = "merchant",
    BANKFRAME_OPENED = "bank",         BANKFRAME_CLOSED = "bank",
    MAIL_SHOW = "mail",                MAIL_CLOSED = "mail",
    TRADE_SHOW = "trade",              TRADE_CLOSED = "trade",
    AUCTION_HOUSE_SHOW = "ah",         AUCTION_HOUSE_CLOSED = "ah",
    GUILDBANKFRAME_OPENED = "gbank",   GUILDBANKFRAME_CLOSED = "gbank",
}
local WINDOW_OPEN = {
    MERCHANT_SHOW = true, BANKFRAME_OPENED = true, MAIL_SHOW = true,
    TRADE_SHOW = true, AUCTION_HOUSE_SHOW = true, GUILDBANKFRAME_OPENED = true,
}

local function SafeRegister(event)
    pcall(f.RegisterEvent, f, event)
end

SafeRegister("ADDON_LOADED")
SafeRegister("PLAYER_ENTERING_WORLD")
SafeRegister("BAG_UPDATE_DELAYED")
SafeRegister("PLAYER_REGEN_ENABLED")
SafeRegister("PLAYER_UNGHOST")
SafeRegister("PLAYER_ALIVE")
SafeRegister("LOOT_OPENED")
SafeRegister("LOOT_READY")
SafeRegister("LOOT_CLOSED")
for ev in pairs(WINDOW_EVENTS) do SafeRegister(ev) end

f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        AutoOpenDB = AutoOpenDB or {}
        db = AutoOpenDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = (type(v) == "table") and {} or v end
        end
        return
    end
    if not db then return end

    if event == "PLAYER_ENTERING_WORLD" then
        wipe(windows); lootOpen = false; busy = nil
        Schedule(3)
    elseif event == "LOOT_OPENED" or event == "LOOT_READY" then
        lootOpen = true
    elseif event == "LOOT_CLOSED" then
        lootOpen = false
        if busy then C_Timer.After(0.5, Finish) else Schedule(OPEN_GAP) end
    elseif WINDOW_EVENTS[event] then
        if WINDOW_OPEN[event] then
            windows[WINDOW_EVENTS[event]] = true
        else
            windows[WINDOW_EVENTS[event]] = nil
            Schedule(0.5)
        end
    else
        Schedule(0.2)
    end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local function ItemIDFrom(msg)
    local id = msg:match("item:(%d+)") or msg:match("^%s*(%d+)%s*$")
    return id and tonumber(id)
end

local function Help()
    Print("commands:")
    print("  /ao              - turn auto-opening on or off")
    print("  /ao status       - show settings and what's waiting to open")
    print("  /ao ignore [item] - never open this item (shift-click it into chat)")
    print("  /ao unignore [item] - allow it again")
    print("  /ao ignored      - list ignored items")
    print("  /ao quiet        - toggle the 'opened ...' chat messages")
    print("  /ao free N       - free bag slots to keep before opening (now " .. db.minFree .. ")")
    print("  /ao retry        - retry items skipped this session")
end

SLASH_AUTOOPEN1 = "/ao"
SLASH_AUTOOPEN2 = "/autoopen"
SlashCmdList.AUTOOPEN = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "toggle" then
        db.enabled = not db.enabled
        Print(db.enabled and "|cff00ff00on|r" or "|cffff4040off|r")
        if db.enabled then Schedule(0.2) end
    elseif cmd == "on" then
        db.enabled = true; Print("|cff00ff00on|r"); Schedule(0.2)
    elseif cmd == "off" then
        db.enabled = false; Print("|cffff4040off|r")
    elseif cmd == "status" then
        local waiting = 0
        for bag = 0, LastBag() do
            for slot = 1, NumSlots(bag) do
                if ShouldOpen(bag, slot) then
                    local _, _, _, count = ItemInfo(bag, slot)
                    waiting = waiting + (count or 1)
                end
            end
        end
        local reason = Blocked()
        Print(("%s, %d waiting to open, %d free slots (keeps %d)%s"):format(
            db.enabled and "|cff00ff00on|r" or "|cffff4040off|r",
            waiting, TotalFree(), db.minFree,
            reason and (", paused: " .. reason) or ""))
    elseif cmd == "ignore" then
        local id = ItemIDFrom(rest)
        if not id then Print("shift-click an item after /ao ignore"); return end
        db.ignore[id] = true
        Print("ignoring " .. (select(2, GetItemInfo(id)) or ("item " .. id)))
    elseif cmd == "unignore" then
        local id = ItemIDFrom(rest)
        if not id then Print("shift-click an item after /ao unignore"); return end
        db.ignore[id] = nil
        skipSession[id] = nil; failures[id] = nil
        Print("no longer ignoring " .. (select(2, GetItemInfo(id)) or ("item " .. id)))
        Schedule(0.2)
    elseif cmd == "ignored" or cmd == "list" then
        local any = false
        for id in pairs(db.ignore) do
            any = true
            print("  " .. (select(2, GetItemInfo(id)) or ("item " .. id)) .. " (" .. id .. ")")
        end
        if not any then Print("nothing ignored") end
    elseif cmd == "quiet" then
        db.announce = not db.announce
        Print("chat messages " .. (db.announce and "on" or "off"))
    elseif cmd == "free" then
        local n = tonumber(rest)
        if not n or n < 0 then Print("usage: /ao free 2"); return end
        db.minFree = math.floor(n)
        Print("will keep " .. db.minFree .. " bag slot(s) free")
        Schedule(0.2)
    elseif cmd == "retry" then
        wipe(skipSession); wipe(failures)
        Print("retrying skipped items")
        Schedule(0.2)
    else
        Help()
    end
end
