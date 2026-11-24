-- TwizErrors bug catcher (1.1.0): catches Lua errors and blocked actions from every addon,
-- like BugGrabber/BugSack, so nothing else needs to be installed.
--   /terr bugs     open the error window (newest first; the text box is ready to copy)
--   /terr clear    forget the saved errors
--   /terr catch    turn catching on / off
local ADDON, NS = ...

local MAX_SAVED = 100        -- errors kept between sessions
local db                     -- TwizErrorsDB (set on load)
local session = 0
local bugs = {}              -- this list == db.bugs
local window
local current = 1
local lastSaid = 0

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff8fe08fTwizErrors|r: " .. tostring(msg)) end
local function plain(v)
    if issecretvalue and issecretvalue(v) then return "<hidden by the game>" end
    return v
end

-- which addon an error came from: the first AddOns/<name>/ in the message, else in the stack
local function AddonOf(msg, stack)
    local function find(s)
        if type(s) ~= "string" then return nil end
        return s:match("[Ii]nterface[/\\][Aa]dd[Oo]ns[/\\]([^/\\]+)[/\\]") or s:match("^([%w_%-!]+)[/\\][^:]+%.lua:%d+")
    end
    return find(msg) or find(stack) or "?"
end
NS.AddonOf = AddonOf

local function Notify(entry)
    if not db or db.quietBugs then return end
    if GetTime and GetTime() - lastSaid < 30 then return end
    lastSaid = GetTime and GetTime() or 0
    Print(("caught an error in |cffffd050%s|r - /terr bugs to see it."):format(entry.addon))
end

local function Record(msg, stack, kind)
    if not db or db.catch == false then return end
    msg = tostring(plain(msg) or "?")
    stack = type(stack) == "string" and stack or ""
    -- the same error again this session: count it instead of a new entry
    for _, b in ipairs(bugs) do
        if b.session == session and b.msg == msg then
            b.count = (b.count or 1) + 1
            b.time = date and date("%H:%M:%S") or b.time
            if window and window:IsShown() then NS.ShowBug(current) end
            return b
        end
    end
    local entry = {
        msg = msg, stack = stack, kind = kind or "error", count = 1, session = session,
        addon = AddonOf(msg, stack), time = date and date("%H:%M:%S") or "",
        day = date and date("%Y-%m-%d") or "",
    }
    table.insert(bugs, 1, entry)
    while #bugs > MAX_SAVED do table.remove(bugs) end
    Notify(entry)
    if window and window:IsShown() then current = 1; NS.ShowBug(1) end
    return entry
end
NS.Record = Record

-- errors this session (all addons, or one)
function NS.BugCount(addon)
    local n = 0
    for _, b in ipairs(bugs) do
        if b.session == session and (not addon or b.addon == addon) then n = n + (b.count or 1) end
    end
    return n
end

------------------------------------------------------------------------
-- catching
------------------------------------------------------------------------
local hooked
local function Hook()
    if hooked or not seterrorhandler or not geterrorhandler then return end
    hooked = true
    local ok, prev = pcall(geterrorhandler)
    if not ok then prev = nil end
    pcall(seterrorhandler, function(msg, ...)
        local stack = debugstack and debugstack(3) or ""
        pcall(Record, msg, stack, "error")
        if prev then return prev(msg, ...) end
    end)
end
Hook() -- as early as possible: errors from addons that load after TwizErrors are caught too

local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "MACRO_ACTION_BLOCKED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        TwizErrorsDB = TwizErrorsDB or {}
        db = TwizErrorsDB
        db.bugs = db.bugs or {}
        bugs = db.bugs
        db.session = (db.session or 0) + 1
        session = db.session
        -- anything caught before the saved list was loaded
        for i = #NS.early, 1, -1 do local e = NS.early[i]; Record(e[1], e[2], e[3]) end
        NS.early = {}
        return
    end
    -- the game blocked an addon from doing something only Blizzard's code may do (taint)
    local who = plain(a1) or "?"
    local what = plain(a2) or "?"
    local msg = ("%s was blocked from calling %s()"):format(tostring(who), tostring(what))
    local entry = Record(msg, debugstack and debugstack(2) or "", "blocked")
    if entry and entry.addon == "?" then entry.addon = tostring(who) end
end)

-- before ADDON_LOADED the saved list doesn't exist yet: queue
NS.early = {}
local realRecord = Record
Record = function(msg, stack, kind)
    if not db then NS.early[#NS.early + 1] = { msg, stack, kind }; return end
    return realRecord(msg, stack, kind)
end
NS.Record = Record

------------------------------------------------------------------------
-- the window
------------------------------------------------------------------------
local function Text(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if fs.SetFont then pcall(fs.SetFont, fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12, "") end
    fs:SetTextColor(r or 0.92, g or 0.92, b or 0.92)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Build()
    window = CreateFrame("Frame", "TwizErrorsBugFrame", UIParent, "BackdropTemplate")
    window:SetSize(620, 380)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true); window:EnableMouse(true); window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetClampedToScreen(true)
    if window.SetBackdrop then
        window:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        window:SetBackdropColor(0.07, 0.08, 0.10, 0.97); window:SetBackdropBorderColor(0.25, 0.27, 0.32, 1)
    end
    if UISpecialFrames then table.insert(UISpecialFrames, "TwizErrorsBugFrame") end
    window:Hide()

    window.title = Text(window, 14, 0.56, 0.88, 0.56)
    window.title:SetPoint("TOPLEFT", 12, -10)
    window.head = Text(window, 11, 0.75, 0.77, 0.8)
    window.head:SetPoint("TOPLEFT", 12, -30); window.head:SetPoint("RIGHT", -12, 0)
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    -- the error text: an edit box, so you can select it and Ctrl+C
    local scroll = CreateFrame("ScrollFrame", "TwizErrorsBugScroll", window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -50); scroll:SetPoint("BOTTOMRIGHT", -32, 44)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true); box:SetAutoFocus(false)
    if box.SetFontObject then box:SetFontObject(ChatFontNormal or GameFontHighlightSmall) end
    box:SetWidth(570)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); window:Hide() end)
    box:SetScript("OnTextChanged", function(self, user) if user then NS.ShowBug(current) end end) -- read-only
    scroll:SetScrollChild(box)
    window.box = box

    local function Btn(label, w, x, fn)
        local b = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        b:SetSize(w, 22); b:SetPoint("BOTTOMLEFT", x, 12); b:SetText(label)
        b:SetScript("OnClick", fn)
        return b
    end
    window.prev = Btn("< Newer", 90, 12, function() NS.ShowBug(current - 1) end)
    window.next = Btn("Older >", 90, 106, function() NS.ShowBug(current + 1) end)
    Btn("Select all (Ctrl+C)", 150, 200, function() box:SetFocus(); box:HighlightText() end)
    Btn("Clear", 70, 354, function() NS.Clear(); NS.ShowBug(1) end)
    window.count = Text(window, 11, 0.6, 0.62, 0.66)
    window.count:SetPoint("BOTTOMRIGHT", -14, 17)
end

function NS.ShowBug(i)
    if not window then Build() end
    local n = #bugs
    if n == 0 then
        window.title:SetText("TwizErrors - no errors caught")
        window.head:SetText("Nothing has gone wrong. Errors from every addon land here.")
        window.box:SetText("")
        window.count:SetText("")
        window.prev:Disable(); window.next:Disable()
        return
    end
    current = math.max(1, math.min(n, i or 1))
    local b = bugs[current]
    window.title:SetText(("TwizErrors - error in %s"):format(b.addon))
    window.head:SetText(("%s %s   x%d   %s%s"):format(b.day or "", b.time or "", b.count or 1,
        b.kind == "blocked" and "blocked action" or "Lua error", b.session == session and "   (this session)" or ""))
    window.box:SetText(("%s\n\n%s"):format(b.msg, b.stack ~= "" and b.stack or "(no stack)"))
    if window.box.SetCursorPosition then window.box:SetCursorPosition(0) end
    window.count:SetText(("%d of %d   (%d this session)"):format(current, n, NS.BugCount()))
    if current > 1 then window.prev:Enable() else window.prev:Disable() end
    if current < n then window.next:Enable() else window.next:Disable() end
end

function NS.ToggleBugs()
    if not window then Build() end
    if window:IsShown() then window:Hide() else window:Show(); NS.ShowBug(1) end
end

function NS.Clear()
    for i = #bugs, 1, -1 do bugs[i] = nil end
end

function NS.BugsCmd(cmd)
    if cmd == "bugs" or cmd == "errors" then NS.ToggleBugs(); return true end
    if cmd == "clear" then NS.Clear(); Print("saved errors cleared."); return true end
    if cmd == "catch" then
        db.catch = db.catch == false
        Print("error catching " .. (db.catch and "on" or "off")); return true
    end
    if cmd == "quietbugs" then
        db.quietBugs = not db.quietBugs
        Print("\"caught an error\" chat line " .. (db.quietBugs and "off" or "on")); return true
    end
end
