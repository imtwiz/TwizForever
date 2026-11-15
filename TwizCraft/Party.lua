-- TwizCraft party crafters: party members running TwizCraft share their
-- professions, skill levels and learned recipes. Browse them in the Party
-- window (/tc party or the Party button), and item tooltips tell you who in
-- your party can make that item. Members also share how many crafting
-- materials they hold (bags + bank + mailbox), so the window shows how many
-- of every recipe the party can make with everyone's materials combined.
local ADDON, NS = ...

local PREFIX = "TWZC"
local VERSION = 2
NS.partyProfs = {}       -- [name] = { profs = { [line] = { name, skill, max, recipes = { [id] = outItemID }, mats = { [id] = { made, {rid, qty}... } } } }, inv = { [itemID] = n }, synced }

local function Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
-- a unit name without its realm ("Bob-SomeRealm" -> "Bob")
local function Short(name) return name and (name:gsub("%-.*$", "")) or name end
-- dungeon-finder groups talk on INSTANCE_CHAT, normal parties on PARTY
local function Channel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
        and not (LE_PARTY_CATEGORY_HOME and IsInGroup(LE_PARTY_CATEGORY_HOME)) then
        return "INSTANCE_CHAT"
    end
    return "PARTY"
end
local CHANNELS = { PARTY = true, INSTANCE_CHAT = true, RAID = true }
local function InGroup() return IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()) end

------------------------------------------------------------------------
-- Names. On Forever characters have surnames: an addon message arrives from
-- "First Last" (or "First-Last", with or without "-Realm"), while UnitName()
-- gives only "First". So a sender is matched to a party unit, never compared
-- as text.
------------------------------------------------------------------------
local function Norm(name) return (name:lower():gsub("[%s%-]+", " ")) end

-- sender is exactly this name, or this name followed by more words
local function Fits(sender, name)
    return name ~= "" and (sender == name or sender:sub(1, #name + 1) == name .. " ")
end

-- { { unit = "party1", name = "Bob" }, ... }: the name each party member is
-- listed under. Two members with the same first name are listed in full.
local function Roster()
    local list, seen = {}, {}
    for i = 1, 4 do
        local unit = "party" .. i
        local first = NS.safe(UnitName(unit))
        if first then
            first = Short(first)
            list[#list + 1] = { unit = unit, name = first }
            seen[first] = (seen[first] or 0) + 1
        end
    end
    for _, m in ipairs(list) do
        if seen[m.name] > 1 then
            m.name = NS.safe(GetUnitName and GetUnitName(m.unit, true)) or (m.name .. " (" .. m.unit .. ")")
        end
    end
    return list
end

-- How well a sender name fits a unit: 2 = its full name, 1 = its first name
local function Match(sender, unit)
    local first = NS.safe(UnitName(unit))
    if not first then return 0 end
    local full = NS.safe(GetUnitName and GetUnitName(unit, true))
    if full and Fits(sender, Norm(full)) then return 2 end
    return Fits(sender, Norm(first)) and 1 or 0
end

-- The roster name of whoever sent an addon message; false when it was you,
-- nil when it is nobody in your party (or can't be told apart).
local function Member(sender)
    sender = NS.safe(sender)
    if type(sender) ~= "string" then return nil end
    sender = Norm(sender)
    local best, bestName, tied = Match(sender, "player"), false, false
    for _, m in ipairs(Roster()) do
        local score = Match(sender, m.unit)
        if score > best then best, bestName, tied = score, m.name, false
        elseif score == best and score > 0 then tied = true end
    end
    if best == 0 or tied then return nil end
    return bestName
end

------------------------------------------------------------------------
-- Sending, paced so the game never throttles us
------------------------------------------------------------------------
local sendQ, sending = {}, false
local function Pump()
    local m = table.remove(sendQ, 1)
    if not m then sending = false; return end
    if InGroup() and C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(PREFIX, m, Channel()) end
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
                if r.learned then
                    local mats = {}
                    for _, g in ipairs(r.reagents or {}) do mats[#mats + 1] = g.id .. "*" .. (g.qty or 1) end
                    list[#list + 1] = ("%d:%d:%d:%s"):format(id, r.out or 0, r.made or 1, table.concat(mats, "/"))
                end
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

local SendInvFull
local function SendAll()
    Send("B|" .. VERSION)
    for line, p in pairs(Mine()) do SendProf(line, p) end
    Send("E")
    if SendInvFull then SendInvFull() end
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
-- Your materials: how many of each item that any recipe in the party uses
-- (yours or a party member's) you hold in bags + bank + mailbox
------------------------------------------------------------------------
local function MaterialIDs()
    local ids = {}
    for _, p in pairs(NS.Char().profs or {}) do
        for _, r in pairs(p.recipes or {}) do
            if r.learned then for _, g in ipairs(r.reagents or {}) do ids[g.id] = true end end
        end
    end
    for _, m in pairs(NS.partyProfs) do
        for _, p in pairs(m.profs or {}) do
            for _, need in pairs(p.mats or {}) do
                for _, g in ipairs(need) do ids[g[1]] = true end
            end
        end
    end
    return ids
end

local sentInv = {}
local function SendInv(full)
    local chunk, len = {}, 0
    local function flush()
        if #chunk > 0 then Send("I|" .. table.concat(chunk, ",")) end
        chunk, len = {}, 0
    end
    local ids = MaterialIDs()
    for id in pairs(sentInv) do ids[id] = true end      -- so used-up items go to 0
    for id in pairs(ids) do
        local n = NS.Owned(id)
        if full and n > 0 or (not full and (sentInv[id] or 0) ~= n) then
            local e = id .. ":" .. n
            if len + #e + 1 > 230 then flush() end
            chunk[#chunk + 1] = e; len = len + #e + 1
        end
        sentInv[id] = (n > 0) and n or nil
    end
    flush()
end

SendInvFull = function() wipe(sentInv); SendInv(true) end

local invTimer
function NS.PartyInvChanged()
    if not InGroup() or invTimer then return end
    invTimer = true
    C_Timer.After(5, function() invTimer = nil; SendInv(false) end)
end

------------------------------------------------------------------------
-- Receiving
------------------------------------------------------------------------
local lastFull = 0
local function OnMessage(msg, sender)
    local who = Member(sender)
    if not who then return end -- yourself, or nobody in your party
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
            p.mats = p.mats or {}
            for entry in list:gmatch("[^,]+") do
                local id, out, made, mats = entry:match("^(%d+):(%d+):?(%d*):?(.*)$")
                if id then
                    id = tonumber(id)
                    p.recipes[id] = tonumber(out)
                    local need = { made = tonumber(made) or 1 }
                    for rid, qty in (mats or ""):gmatch("(%d+)%*(%d+)") do need[#need + 1] = { tonumber(rid), tonumber(qty) } end
                    if #need > 0 then p.mats[id] = need end
                end
            end
        end
        if not m.incoming and NS.RefreshPartyCrafters then NS.RefreshPartyCrafters() end
        NS.PartyInvChanged()
    elseif kind == "I" then
        m.inv = m.inv or {}
        for id, n in rest:gmatch("(%d+):(%d+)") do
            n = tonumber(n)
            m.inv[tonumber(id)] = (n > 0) and n or nil
        end
        if NS.RefreshPartyCrafters then NS.RefreshPartyCrafters() end
    elseif kind == "E" then
        if m.incoming then m.profs, m.incoming = m.incoming, nil end
        NS.PartyInvChanged()
        local first = not m.synced
        m.synced = true
        if first then
            local names = {}
            for _, p in pairs(m.profs) do names[#names + 1] = ("%s %d"):format(p.name, p.skill) end
            table.sort(names)
            NS.Print(("%s's professions: %s (/tc party to browse)."):format(who, #names > 0 and table.concat(names, ", ") or "none"))
        end
        if NS.RefreshPartyCrafters then NS.RefreshPartyCrafters() end
        if NS.RefreshUI then NS.RefreshUI() end
    end
end

------------------------------------------------------------------------
-- Group changes
------------------------------------------------------------------------
local members = {}
local function RosterChanged()
    local here = {}
    if InGroup() then
        for _, m in ipairs(Roster()) do here[m.name] = true end
    end
    for name in pairs(NS.partyProfs) do
        if not here[name] then NS.partyProfs[name] = nil end
    end
    if not InGroup() then wipe(members); wipe(sentSig); if NS.RefreshUI then NS.RefreshUI() end return end
    local now, joined = {}, false
    for _, m in ipairs(Roster()) do
        now[m.name] = true
        if not members[m.name] then joined = true end
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

-- party-wide count of an item: you + every synced member
function NS.PartyHave(id)
    local total, who = NS.Owned(id), {}
    if total > 0 then who[#who + 1] = ("you %d"):format(total) end
    for name, m in pairs(NS.partyProfs) do
        local n = m.inv and m.inv[id] or 0
        if n > 0 then total = total + n; who[#who + 1] = ("%s %d"):format(name, n) end
    end
    return total, who
end

-- how many crafts of a party recipe everyone's materials cover
function NS.PartyCanMake(need)
    if not need or #need == 0 then return nil end
    local n = math.huge
    for _, g in ipairs(need) do n = math.min(n, math.floor(NS.PartyHave(g[1]) / math.max(1, g[2]))) end
    return n == math.huge and 0 or n
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
local makeableOnly = false
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
                local need = p.mats and p.mats[id]
                local can = NS.PartyCanMake(need)
                if (f == "" or rn:lower():find(f, 1, true)) and (not makeableOnly or (can or 0) > 0) then
                    list[#list + 1] = { id = id, out = out, name = rn, need = need, can = can }
                end
            end
            table.sort(list, function(a, b) return a.name < b.name end)
            local key = name .. ":" .. line
            local expanded = open[key] or f ~= "" or makeableOnly
            if (f == "" and not makeableOnly) or #list > 0 then
                rows[#rows + 1] = { kind = "prof", key = key, text = ("  %s %s |cff66ff66%d/%d|r |cff999999%d recipes|r"):format(
                    expanded and "-" or "+", p.name, p.skill, p.max, Count(p.recipes)) }
                if expanded then
                    for _, r in ipairs(list) do
                        local mine = NS.Char().profs[line]
                        local iKnow = mine and mine.recipes[r.id] and mine.recipes[r.id].learned
                        rows[#rows + 1] = { kind = "recipe", out = r.out, need = r.need, crafter = name,
                            text = ("      %s%s"):format(r.name, iKnow and "" or " |cff66ccff(you don't know)|r"),
                            right = r.can and (r.can > 0 and ("|cff66ff66x%d|r"):format(r.can) or "|cff777777-|r") or "" }
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
            l.right:SetText(r.right or "")
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
    win:SetSize(400, 64 + NLINES * LINE_H)
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
    local cb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    cb:SetSize(20, 20); cb:SetPoint("BOTTOMLEFT", 8, 4)
    cb:SetScript("OnClick", function(self) makeableOnly = self:GetChecked() and true or false; offset = 0; Draw() end)
    local cbt = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cbt:SetPoint("LEFT", cb, "RIGHT", 2, 0); cbt:SetText("Only what the party has materials for")
    win.count = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.count:SetPoint("BOTTOMRIGHT", -10, 8)
    for i = 1, NLINES do
        local l = CreateFrame("Button", nil, win)
        l:SetSize(380, LINE_H); l:SetPoint("TOPLEFT", 10, -30 - (i - 1) * LINE_H)
        l.right = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l.right:SetPoint("RIGHT"); l.right:SetJustifyH("RIGHT")
        l.text = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l.text:SetPoint("LEFT"); l.text:SetPoint("RIGHT", -40, 0); l.text:SetJustifyH("LEFT"); l.text:SetWordWrap(false)
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
            if d and d.kind == "recipe" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if d.out and d.out > 0 then GameTooltip:SetItemByID(d.out) end
                if d.need then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(("Made by %s - materials across the party:"):format(d.crafter), 0.4, 0.8, 1)
                    for _, g in ipairs(d.need) do
                        local have, who = NS.PartyHave(g[1])
                        local ok = have >= g[2]
                        GameTooltip:AddDoubleLine(("%dx %s"):format(g[2], NS.ItemName(g[1])),
                            (#who > 0 and table.concat(who, ", ") or "nobody has any"),
                            ok and 0.4 or 1, ok and 1 or 0.4, 0.4, 0.8, 0.8, 0.8)
                    end
                end
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
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("BANKFRAME_CLOSED")
ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if event == "BAG_UPDATE_DELAYED" or event == "BANKFRAME_CLOSED" then NS.PartyInvChanged(); return end
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
        C_Timer.After(4, RosterChanged)
    elseif event == "GROUP_ROSTER_UPDATE" then
        RosterChanged()
    elseif event == "CHAT_MSG_ADDON" then
        if a1 == PREFIX and CHANNELS[a3] then OnMessage(a2, a4) end
    end
end)
