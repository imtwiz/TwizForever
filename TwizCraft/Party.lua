-- TwizCraft party crafters: party members running TwizCraft share their
-- professions, skill levels and learned recipes. Browse them in the Party
-- window (/cr party or the Party button), and item tooltips tell you who in
-- your party can make that item.
local ADDON, NS = ...

local PREFIX = "TWZC"
local VERSION = 1
NS.partyProfs = {}       -- [name] = { profs = { [line] = { name, skill, max, recipes = { [id] = outItemID } } }, synced }

local function Me() return UnitName("player") end
local function Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
local function Short(n) return Ambiguate and Ambiguate(n, "none") or n end
local function InGroup() return IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()) end

------------------------------------------------------------------------
-- Sending, paced so the game never throttles us
------------------------------------------------------------------------
local sendQ, sending = {}, false
local function Pump()
    local m = table.remove(sendQ, 1)
    if not m then sending = false; return end
    if InGroup() and C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(PREFIX, m, "PARTY") end
    C_Timer.After(0.15, Pump)
end
local function Send(m)
    if not InGroup() or (NS.db and NS.db.partyShare == false) then return end
    sendQ[#sendQ + 1] = m
    if not sending then sending = true; C_Timer.After(0.05, Pump) end
end

-- your professions as they are now: { [line] = { name, skill, max, list = { "id:out", ... }, sig } }
local function Mine()
    local out = {}
    local live = {}
    for _, p in ipairs(NS.Professions and NS.Professions() or {}) do live[p.name] = p end
    for line, p in pairs(NS.Char().profs or {}) do
        if line ~= 0 and p.name and p.name ~= "" then
            local list = {}
            for id, r in pairs(p.recipes or {}) do
                if r.learned then list[#list + 1] = id .. ":" .. (r.out or 0) end
            end
            table.sort(list)
            local lp = live[p.name]
            out[line] = { name = p.name, skill = lp and lp.skill or 0, max = lp and lp.max or 0, list = list,
                          sig = #list .. ":" .. (list[1] or "") .. (list[#list] or "") .. ":" .. (lp and lp.skill or 0) }
        end
    end
    return out
end

local sentSig = {}
local function SendProf(line, p)
    Send(("P|%d|%d|%d|%s"):format(line, p.skill, p.max, p.name))
    local chunk = {}
    local len = 0
    for _, e in ipairs(p.list) do
        if len + #e + 1 > 230 then
            Send(("R|%d|%s"):format(line, table.concat(chunk, ",")))
            chunk, len = {}, 0
        end
        chunk[#chunk + 1] = e; len = len + #e + 1
    end
    if #chunk > 0 then Send(("R|%d|%s"):format(line, table.concat(chunk, ","))) end
    sentSig[line] = p.sig
end

local function SendAll()
    Send("B|" .. VERSION)
    for line, p in pairs(Mine()) do SendProf(line, p) end
    Send("E")
end

-- after a profession window is read: send only professions that changed
local changeTimer
function NS.PartyRecipesChanged()
    if not InGroup() or changeTimer then return end
    changeTimer = true
    C_Timer.After(3, function()
        changeTimer = nil
        for line, p in pairs(Mine()) do
            if sentSig[line] ~= p.sig then SendProf(line, p) end
        end
    end)
end

------------------------------------------------------------------------
-- Receiving
------------------------------------------------------------------------
local lastFull = 0
local function OnMessage(msg, sender)
    local who = Short(sender)
    if who == Me() then return end
    local kind, rest = msg:match("^(%a)|?(.*)$")
    if not kind then return end
    local m = NS.partyProfs[who]
    if not m then m = { profs = {} }; NS.partyProfs[who] = m end
    if kind == "H" then
        if GetTime() - lastFull > 3 then lastFull = GetTime(); C_Timer.After(0.5 + math.random(), SendAll) end
    elseif kind == "B" then
        m.incoming = {}
    elseif kind == "P" then
        local line, skill, max, name = rest:match("^(%d+)|(%d+)|(%d+)|(.+)$")
        if line then
            local t = m.incoming or m.profs
            t[tonumber(line)] = { name = name, skill = tonumber(skill), max = tonumber(max), recipes = {} }
        end
    elseif kind == "R" then
        local line, list = rest:match("^(%d+)|(.*)$")
        local t = m.incoming or m.profs
        local p = line and t[tonumber(line)]
        if p then
            for id, out in list:gmatch("(%d+):(%d+)") do p.recipes[tonumber(id)] = tonumber(out) end
        end
        if not m.incoming and NS.RefreshPartyCrafters then NS.RefreshPartyCrafters() end
    elseif kind == "E" then
        if m.incoming then m.profs, m.incoming = m.incoming, nil end
        local first = not m.synced
        m.synced = true
        if first then
            local names = {}
            for _, p in pairs(m.profs) do names[#names + 1] = ("%s %d"):format(p.name, p.skill) end
            table.sort(names)
            NS.Print(("%s's professions: %s (/cr party to browse)."):format(who, #names > 0 and table.concat(names, ", ") or "none"))
        end
        if NS.RefreshPartyCrafters then NS.RefreshPartyCrafters() end
        if NS.RefreshUI then NS.RefreshUI() end
    end
end

------------------------------------------------------------------------
-- Group changes
------------------------------------------------------------------------
local members = {}
local function Roster()
    for name in pairs(NS.partyProfs) do
        if not (InGroup() and UnitInParty(name)) then NS.partyProfs[name] = nil end
    end
    if not InGroup() then wipe(members); wipe(sentSig); if NS.RefreshUI then NS.RefreshUI() end return end
    local now, joined = {}, false
    for i = 1, 4 do
        local n = UnitName("party" .. i)
        if n then n = Short(n); now[n] = true; if not members[n] then joined = true end end
    end
    members = now
    if joined then
        Send("H|" .. VERSION)
        lastFull = GetTime(); C_Timer.After(1, SendAll)
    end
    if NS.RefreshUI then NS.RefreshUI() end
end

function NS.PartyCrafterCount()
    local n = 0
    for _, m in pairs(NS.partyProfs) do if m.synced then n = n + 1 end end
    return n
end

-- who in your party can make itemID: { "Bob (Engineering)", ... }
function NS.PartyMakers(itemID)
    local out = {}
    for name, m in pairs(NS.partyProfs) do
        for _, p in pairs(m.profs) do
            for _, o in pairs(p.recipes) do
                if o == itemID then out[#out + 1] = ("%s (%s)"):format(name, p.name); break end
            end
        end
    end
    table.sort(out)
    return out
end

------------------------------------------------------------------------
-- Tooltips: "Party can make: Bob (Engineering)"
------------------------------------------------------------------------
local function AddMakers(tt, itemID)
    if not itemID or NS.PartyCrafterCount() == 0 then return end
    local makers = NS.PartyMakers(itemID)
    if #makers > 0 then tt:AddLine("|cff66ccffParty can make:|r " .. table.concat(makers, ", "), 1, 1, 1, true) end
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
        if tt == GameTooltip or tt == ItemRefTooltip then AddMakers(tt, data and data.id) end
    end)
elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", function(tt)
        local _, link = tt:GetItem()
        local id = link and tonumber(link:match("item:(%d+)"))
        AddMakers(tt, id)
    end)
end

------------------------------------------------------------------------
-- Party crafters window
------------------------------------------------------------------------
local win, lines, open, filter = nil, {}, {}, ""
local LINE_H, NLINES = 16, 22
local offset = 0

local function RecipeName(line, id, out)
    local mine = NS.Char().profs[line]
    local r = mine and mine.recipes[id]
    if r and r.name then return r.name end
    local n = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id))
    if n then return n end
    local item = out and out > 0 and C_Item.GetItemInfo(out)
    return item or ("recipe " .. id)
end

local function Rows()
    local rows = {}
    local names = {}
    for name, m in pairs(NS.partyProfs) do if m.synced then names[#names + 1] = name end end
    table.sort(names)
    local f = filter:lower()
    for _, name in ipairs(names) do
        local m = NS.partyProfs[name]
        rows[#rows + 1] = { kind = "member", text = ("|cffffd100%s|r"):format(name) }
        local lines2 = {}
        for line in pairs(m.profs) do lines2[#lines2 + 1] = line end
        table.sort(lines2, function(a, b) return m.profs[a].name < m.profs[b].name end)
        for _, line in ipairs(lines2) do
            local p = m.profs[line]
            local list = {}
            for id, out in pairs(p.recipes) do
                local rn = RecipeName(line, id, out)
                if f == "" or rn:lower():find(f, 1, true) then list[#list + 1] = { id = id, out = out, name = rn } end
            end
            table.sort(list, function(a, b) return a.name < b.name end)
            local key = name .. ":" .. line
            local expanded = open[key] or f ~= ""
            if f == "" or #list > 0 then
                rows[#rows + 1] = { kind = "prof", key = key, text = ("  %s %s |cff66ff66%d/%d|r |cff999999%d recipes|r"):format(
                    expanded and "-" or "+", p.name, p.skill, p.max, Count(p.recipes)) }
                if expanded then
                    for _, r in ipairs(list) do
                        local mine = NS.Char().profs[line]
                        local iKnow = mine and mine.recipes[r.id] and mine.recipes[r.id].learned
                        rows[#rows + 1] = { kind = "recipe", out = r.out, text = ("      %s%s"):format(r.name,
                            iKnow and "" or " |cff66ccff(you don't know)|r") }
                    end
                end
            end
        end
    end
    if #rows == 0 then rows[1] = { kind = "info", text = "|cff999999No one in your party runs TwizCraft yet.|r" } end
    return rows
end

local function Draw()
    if not win or not win:IsShown() then return end
    local rows = Rows()
    offset = math.max(0, math.min(offset, #rows - NLINES))
    for i = 1, NLINES do
        local r, l = rows[i + offset], lines[i]
        if r then
            l.data = r
            l.text:SetText(r.text)
            l:Show()
        else
            l:Hide()
        end
    end
    win.count:SetText(#rows > NLINES and ("%d-%d of %d"):format(offset + 1, math.min(#rows, offset + NLINES), #rows) or "")
end
NS._partyRows = function() return Rows() end
NS._partyOpen = open
NS.RefreshPartyCrafters = function() if win and win:IsShown() then Draw() end end

local function Build()
    win = CreateFrame("Frame", "TwizCraftPartyFrame", UIParent, "BackdropTemplate")
    win:SetSize(380, 60 + NLINES * LINE_H)
    win:SetPoint("CENTER", 200, 40)
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton"); win:SetClampedToScreen(true)
    win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
    if win.SetBackdrop then
        win:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        win:SetBackdropColor(0, 0, 0, 0.9)
    end
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8); title:SetText("Party crafters")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    local search = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    search:SetSize(150, 18); search:SetPoint("TOPRIGHT", -30, -6); search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self) filter = self:GetText() or ""; offset = 0; Draw() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("RIGHT", search, "LEFT", -8, 0); hint:SetText("search")
    win.count = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.count:SetPoint("BOTTOMRIGHT", -10, 8)
    for i = 1, NLINES do
        local l = CreateFrame("Button", nil, win)
        l:SetSize(360, LINE_H); l:SetPoint("TOPLEFT", 10, -30 - (i - 1) * LINE_H)
        l.text = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l.text:SetPoint("LEFT"); l.text:SetPoint("RIGHT"); l.text:SetJustifyH("LEFT"); l.text:SetWordWrap(false)
        local hl = l:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.07)
        l:SetScript("OnClick", function(self)
            local d = self.data
            if d and d.kind == "prof" then open[d.key] = not open[d.key]; Draw()
            elseif d and d.kind == "recipe" and d.out and d.out > 0 and IsModifiedClick("CHATLINK") then
                local _, link = C_Item.GetItemInfo(d.out)
                if link then ChatEdit_InsertLink(link) end
            end
        end)
        l:SetScript("OnEnter", function(self)
            local d = self.data
            if d and d.kind == "recipe" and d.out and d.out > 0 then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(d.out)
                GameTooltip:Show()
            end
        end)
        l:SetScript("OnLeave", function() GameTooltip:Hide() end)
        lines[i] = l
    end
    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(_, delta) offset = offset - delta * 3; Draw() end)
    win:Hide()
end

function NS.TogglePartyCrafters()
    if not win then Build() end
    if win:IsShown() then win:Hide() else win:Show(); Draw() end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
        C_Timer.After(4, Roster)
    elseif event == "GROUP_ROSTER_UPDATE" then
        Roster()
    elseif event == "CHAT_MSG_ADDON" then
        if a1 == PREFIX and a3 == "PARTY" then OnMessage(a2, a4) end
    end
end)
