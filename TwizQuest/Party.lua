-- TwizQuest party sync: party members running TwizQuest share their quest logs
-- and objective progress over hidden addon messages. The planner uses it to
-- favour quests you share, keep you at a kill spot while a friend still needs
-- kills, and the party line shows who's missing a quest, who's behind, and
-- what's ready to turn in together. Quests a friend lacks can be shared.
local ADDON, NS = ...

local PREFIX = "TWZQ"
local VERSION = 1
NS.partyStats = { sent = 0, recv = 0 }
NS.party = {}            -- [name] = { quests = { [id] = { c = bool, o = { {t, f, r}, ... } } }, level, step, synced, at }
local mine = {}          -- [id] = encoded string last sent
local sendQ, sending = {}, false
local offered = {}       -- [name .. id] = true: quests already shared with that member this session

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

-- the unit of a roster name (for class colors and the like)
function NS.PartyUnit(name)
    for _, m in ipairs(Roster()) do
        if m.name == name then return m.unit end
    end
end

------------------------------------------------------------------------
-- Sending (paced so the game never throttles us)
------------------------------------------------------------------------
local function Pump()
    local msg = table.remove(sendQ, 1)
    if not msg then sending = false; return end
    if InGroup() and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, Channel())
        NS.partyStats.sent = NS.partyStats.sent + 1
    end
    C_Timer.After(0.12, Pump)
end

local function Send(msg)
    if not (NS.db and NS.db.party) or not InGroup() then return end
    sendQ[#sendQ + 1] = msg
    if not sending then sending = true; C_Timer.After(0.05, Pump) end
end

------------------------------------------------------------------------
-- Your quest log, encoded: "id|complete|m3/8,i1/5"
------------------------------------------------------------------------
local TYPE = { monster = "m", item = "i", object = "o", event = "e", log = "e" }

local function Snapshot()
    local out = {}
    local n = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        local id = info and NS.safe(info.questID)
        if id and id > 0 and not NS.safe(info.isHeader) then
            local parts = {}
            local ok, objs = pcall(C_QuestLog.GetQuestObjectives, id)
            if ok and type(objs) == "table" then
                for _, o in ipairs(objs) do
                    parts[#parts + 1] = ("%s%d/%d"):format(TYPE[o.type] or "x",
                        tonumber(NS.safe(o.numFulfilled)) or 0, tonumber(NS.safe(o.numRequired)) or 0)
                end
            end
            local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)
            out[id] = ("%d|%d|%s"):format(id, done and 1 or 0, table.concat(parts, ","))
        end
    end
    return out
end

-- your XP: "X|level|xp|max|rested|xp per hour from your plan"
local xpTimer
local function SendXP()
    local plan = NS._plan and NS._plan()
    Send(("X|%d|%d|%d|%d|%d"):format(UnitLevel("player") or 0, UnitXP("player") or 0, UnitXPMax("player") or 0,
        (GetXPExhaustion and GetXPExhaustion()) or 0, math.floor(plan and plan.rate or 0)))
end
function NS.QueueXP()
    if xpTimer or not InGroup() then return end
    xpTimer = true
    C_Timer.After(2, function() xpTimer = nil; SendXP() end)
end

local function SendFull()
    SendXP()
    local snap = Snapshot()
    Send("B|" .. VERSION .. "|" .. (UnitLevel("player") or 0))
    for _, enc in pairs(snap) do Send("Q|" .. enc) end
    Send("E")
    mine = snap
end

-- only what changed since last time
local function SendChanges()
    local snap = Snapshot()
    for id, enc in pairs(snap) do
        if mine[id] ~= enc then Send("Q|" .. enc) end
    end
    for id in pairs(mine) do
        if not snap[id] then Send("R|" .. id) end
    end
    mine = snap
end

------------------------------------------------------------------------
-- Receiving
------------------------------------------------------------------------
local function Decode(rest)
    local id, c, objs = rest:match("^(%d+)|(%d)|(.*)$")
    if not id then return end
    local q = { c = c == "1", o = {} }
    for t, f, r in objs:gmatch("(%a)(%d+)/(%d+)") do q.o[#q.o + 1] = { t = t, f = tonumber(f), r = tonumber(r) } end
    return tonumber(id), q
end

local changedAt = 0
local function Changed()
    changedAt = GetTime()
    NS.cache = nil                         -- shared quests feed the planner: rebuild candidates
    if NS.MarkDirty then NS.MarkDirty() end
    if NS.RefreshParty then NS.RefreshParty() end
end

local lastFull = 0
local AutoShare

local function OnMessage(msg, sender)
    NS.partyStats.recv = NS.partyStats.recv + 1
    NS.partyStats.last = tostring(NS.safe(sender) or "?") .. ": " .. msg:sub(1, 40)
    local who = Member(sender)
    if not who then return end -- yourself, or nobody in your party
    local kind, rest = msg:match("^(%a)|?(.*)$")
    if not kind then return end
    local p = NS.party[who]
    if kind == "H" then
        -- someone (re)joined: answer with our whole log (at most every few seconds)
        if GetTime() - lastFull > 3 then lastFull = GetTime(); C_Timer.After(0.5 + math.random(), SendFull) end
        local lvl = tonumber(rest:match("^%d+|(%d+)") or "")
        NS.party[who] = p or { quests = {}, at = GetTime() }
        NS.party[who].level = lvl or NS.party[who].level
        return
    end
    if not p then p = { quests = {}, at = GetTime() }; NS.party[who] = p end
    p.at = GetTime()
    if kind == "B" then
        p.incoming = {}
        p.level = tonumber(rest:match("^%d+|(%d+)") or "") or p.level
    elseif kind == "Q" then
        local id, q = Decode(rest)
        if id then
            if p.incoming then p.incoming[id] = q else p.quests[id] = q; Changed() end
        end
    elseif kind == "R" then
        local id = tonumber(rest)
        if id then p.quests[id] = nil; Changed() end
    elseif kind == "E" then
        if p.incoming then p.quests, p.incoming = p.incoming, nil end
        local first = not p.synced
        p.synced = true
        Changed()
        if first then
            NS.Print(("party sync with %s: %d quests."):format(who, NS.Count(p.quests)))
            C_Timer.After(1, function() AutoShare(who) end)
        end
    elseif kind == "X" then
        local lvl, cur, max, rest, rate = rest:match("^(%d+)|(%d+)|(%d+)|(%d+)|(%d+)")
        if lvl then
            lvl = tonumber(lvl)
            if p.xp and p.xp.level and lvl > p.xp.level then
                NS.Print(("%s reached level %d!"):format(who, lvl))
            end
            p.xp = { level = lvl, cur = tonumber(cur), max = tonumber(max), rest = tonumber(rest),
                     rate = tonumber(rate), at = GetTime() }
            p.level = lvl
            if NS.RefreshParty then NS.RefreshParty() end
        end
    elseif kind == "N" then
        local id, step = rest:match("^(%d+)|(.*)$")
        p.step = id and { id = tonumber(id), text = step } or nil
        if NS.RefreshParty then NS.RefreshParty() end
    end
end

-- /tq party sync: ask everyone to resend and send ours
function NS.PartyResync()
    if not InGroup() then return false end
    Send("H|" .. VERSION .. "|" .. (UnitLevel("player") or 0))
    lastFull = GetTime(); C_Timer.After(0.5, SendFull)
    return true
end

function NS.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

------------------------------------------------------------------------
-- Group membership
------------------------------------------------------------------------
local function Prune()
    local here = {}
    if InGroup() then
        for _, m in ipairs(Roster()) do here[m.name] = true end
    end
    for name in pairs(NS.party) do
        if not here[name] then NS.party[name] = nil end
    end
end

local members = {}
local function RosterChanged()
    Prune()
    if not InGroup() then
        wipe(members); wipe(sendQ); mine = {}
        if NS.RefreshParty then NS.RefreshParty() end
        return
    end
    local now, joined = {}, false
    for _, m in ipairs(Roster()) do
        now[m.name] = true
        if not members[m.name] then joined = true end
    end
    members = now
    if joined then
        Send("H|" .. VERSION .. "|" .. (UnitLevel("player") or 0))
        lastFull = GetTime(); C_Timer.After(1, SendFull)
    end
    if NS.RefreshParty then NS.RefreshParty() end
end

------------------------------------------------------------------------
-- What the planner and the party line use
------------------------------------------------------------------------
-- members with TwizQuest who have this quest
function NS.PartyHas(id)
    local n, names = 0, {}
    for name, p in pairs(NS.party) do
        if p.quests[id] then n = n + 1; names[#names + 1] = name end
    end
    return n, names
end

-- For each objective of quest id, the most any party member still needs:
-- { ["m1"] = { need = 5, who = "Bob" }, ... } keyed by type letter + ordinal
function NS.PartyNeed(id)
    if not (NS.db and NS.db.partyHelp) then return nil end
    local out
    for name, p in pairs(NS.party) do
        local q = p.quests[id]
        if q and not q.c then
            local ord = {}
            for _, o in ipairs(q.o) do
                ord[o.t] = (ord[o.t] or 0) + 1
                local need = (o.r or 0) - (o.f or 0)
                local key = o.t .. ord[o.t]
                if need > 0 and (o.t == "m" or o.t == "i") then
                    out = out or {}
                    if not out[key] or need > out[key].need then out[key] = { need = need, who = name } end
                end
            end
        end
    end
    return out
end

-- Summary for the party line: members, quests to share, who's behind, ready together
function NS.PartyStatus()
    local st = { members = {}, missing = {}, theyHave = {}, behind = {}, ready = {}, noAddon = {} }
    if not InGroup() then return st end
    for _, m in ipairs(Roster()) do
        local s = m.name
        if NS.party[s] and NS.party[s].synced then st.members[#st.members + 1] = s
        else st.noAddon[#st.noAddon + 1] = s end
    end
    local log = Snapshot()
    for id in pairs(log) do
        local myDone = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)
        local allDone = myDone
        for _, name in ipairs(st.members) do
            local q = NS.party[name].quests[id]
            if not q then
                local push = C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(id)
                if push then st.missing[#st.missing + 1] = { id = id, who = name } end
            elseif not q.c then
                allDone = false
                local left = {}
                for _, o in ipairs(q.o) do
                    if (o.f or 0) < (o.r or 0) then left[#left + 1] = ("%d/%d"):format(o.f, o.r) end
                end
                if myDone then st.behind[#st.behind + 1] = { id = id, who = name, left = table.concat(left, ", ") } end
            end
        end
        if allDone and #st.members > 0 then
            local shared = false
            for _, name in ipairs(st.members) do if NS.party[name].quests[id] then shared = true end end
            if shared then st.ready[#st.ready + 1] = id end
        end
    end
    for _, name in ipairs(st.members) do
        for id in pairs(NS.party[name].quests) do
            if not log[id] then st.theyHave[#st.theyHave + 1] = { id = id, who = name } end
        end
    end
    return st
end

------------------------------------------------------------------------
-- Sharing quests your friends don't have
------------------------------------------------------------------------
local shareQ, sharing = {}, false
local function ShareNext()
    local id = table.remove(shareQ, 1)
    if not id then sharing = false; if NS.RefreshParty then NS.RefreshParty() end return end
    if InGroup() and not InCombatLockdown() and C_QuestLog.SetSelectedQuest and QuestLogPushQuest then
        C_QuestLog.SetSelectedQuest(id)
        QuestLogPushQuest()
    end
    C_Timer.After(0.5, ShareNext)
end

-- share every quest some synced member lacks (or only those `who` lacks)
function NS.ShareMissing(who)
    local st = NS.PartyStatus()
    local seen = {}
    for _, m in ipairs(st.missing) do
        if (not who or m.who == who) and not seen[m.id] then
            seen[m.id] = true
            offered[m.who .. m.id] = true
            shareQ[#shareQ + 1] = m.id
        end
    end
    if #shareQ == 0 then return 0 end
    if not sharing then sharing = true; ShareNext() end
    return NS.Count(seen)
end

-- share every quest in your log that can be shared (party members who already
-- have one, or can't take it, simply get told so by the game)
function NS.ShareAll()
    if not InGroup() then return 0, "join a party first" end
    local n = 0
    local count = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, count do
        local info = C_QuestLog.GetInfo(i)
        local id = info and NS.safe(info.questID)
        if id and id > 0 and not NS.safe(info.isHeader)
            and C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(id) then
            shareQ[#shareQ + 1] = id; n = n + 1
        end
    end
    if n > 0 and not sharing then sharing = true; ShareNext() end
    return n
end

AutoShare = function(who)
    if not (NS.db and NS.db.party and NS.db.partyShare) then return end
    local st = NS.PartyStatus()
    local fresh = false
    for _, m in ipairs(st.missing) do
        if m.who == who and not offered[who .. m.id] then fresh = true end
    end
    if fresh then
        local n = NS.ShareMissing(who)
        if n > 0 then NS.Print(("sharing %d quest%s %s doesn't have."):format(n, n == 1 and "" or "s", who)) end
    end
end

-- tell the party where you're heading (step 1 of your plan)
function NS.PartyStep(s)
    if not (s and s.q and s.q.id) then return end
    local txt = (s.role == 1 and "pick up " or s.role == 3 and "turn in " or "") .. (s.q.name or "")
    Send(("N|%d|%s"):format(s.q.id, txt:sub(1, 120)))
    NS.QueueXP()
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("PLAYER_XP_UPDATE")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("UPDATE_EXHAUSTION")
local logTimer
ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
        C_Timer.After(3, RosterChanged)
    elseif event == "GROUP_ROSTER_UPDATE" then
        RosterChanged()
    elseif event == "QUEST_LOG_UPDATE" then
        if InGroup() and not logTimer then
            logTimer = true
            C_Timer.After(0.8, function() logTimer = nil; SendChanges() end)
        end
    elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" or event == "UPDATE_EXHAUSTION" then
        NS.QueueXP()
        if NS.RefreshParty then NS.RefreshParty() end
    elseif event == "CHAT_MSG_ADDON" then
        if a1 == PREFIX and CHANNELS[a3] and NS.db and NS.db.party then OnMessage(a2, a4) end
    end
end)

NS._partyOnMessage = OnMessage   -- for tests
