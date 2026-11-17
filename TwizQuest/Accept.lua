-- TwizQuest auto-accept: takes every quest offered to you - from quest givers,
-- gossip menus, and quests shared by your party. Hold Shift when talking to an
-- NPC to skip it for that conversation. /tq accept turns it on or off.
local ADDON, NS = ...

local function On() return NS.db and NS.db.autoAccept and not IsShiftKeyDown() end

local function LogFull()
    local max = C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept() or 25
    local n = 0
    for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
        local info = C_QuestLog.GetInfo(i)
        if info and not NS.safe(info.isHeader) then n = n + 1 end
    end
    return n >= max
end

local warned = 0
local function Full()
    if not LogFull() then return false end
    if GetTime() - warned > 10 then
        warned = GetTime()
        NS.Print("quest log is full - not auto-accepting. /tq cleanup shows what's worth dropping.")
    end
    return true
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM", "GOSSIP_SHOW", "QUEST_GREETING" }) do
    ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event)
    if not On() then return end
    if event == "QUEST_DETAIL" then
        -- a quest's text is open (from an NPC, an item, or shared by your party)
        if Full() then return end
        local title = GetTitleText and GetTitleText()
        AcceptQuest()
        if title and title ~= "" then NS.Print("accepted: " .. title) end
    elseif event == "QUEST_ACCEPT_CONFIRM" then
        -- escort quests started by a party member
        if Full() then return end
        if ConfirmAcceptQuest then ConfirmAcceptQuest() end
        StaticPopup_Hide("QUEST_ACCEPT")
    elseif event == "GOSSIP_SHOW" then
        if not (C_GossipInfo and C_GossipInfo.GetAvailableQuests) or Full() then return end
        local quests = C_GossipInfo.GetAvailableQuests() or {}
        local q = quests[1]
        if q and q.questID then C_GossipInfo.SelectAvailableQuest(q.questID) end
    elseif event == "QUEST_GREETING" then
        if Full() then return end
        if (GetNumAvailableQuests and GetNumAvailableQuests() or 0) > 0 then SelectAvailableQuest(1) end
    end
end)

------------------------------------------------------------------------
-- Quests the giver doesn't actually offer you.
-- Questie's data can think a quest is available when the game disagrees
-- (another quest needed first, a faction/class/race rule, a one-of-two
-- choice). When you talk to a quest giver the plan sent you to and the quest
-- isn't on offer, TwizQuest remembers that and stops suggesting it - until you
-- level up (or /tq unskip). Right-click a step to skip its quest by hand.
------------------------------------------------------------------------
local function CharKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end
local function Skips()
    NS.db.notOffered = NS.db.notOffered or {}
    local k = CharKey()
    NS.db.notOffered[k] = NS.db.notOffered[k] or {}
    return NS.db.notOffered[k]
end

function NS.IsSkipped(id)
    local s = NS.db and NS.db.notOffered and NS.db.notOffered[CharKey()]
    local e = s and s[id]
    if not e then return false end
    if e.level and e.level ~= UnitLevel("player") then s[id] = nil; return false end -- level up: look again
    return true
end

function NS.SkipQuest(id, why)
    if not id then return end
    Skips()[id] = { level = (why == "manual") and nil or UnitLevel("player"), t = time(), why = why }
    if NS.MarkDirty then NS.MarkDirty() end
    if NS.Replan then NS.Replan(true) end
end

function NS.UnskipAll()
    if NS.db and NS.db.notOffered then NS.db.notOffered[CharKey()] = nil end
    if NS.MarkDirty then NS.MarkDirty() end
    if NS.Replan then NS.Replan(true) end
end

local function NpcID(unit)
    local guid = UnitGUID and NS.safe(UnitGUID(unit or "npc"))
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

-- plan pick-ups this NPC should give you
local function PlannedFrom(npc)
    local out, plan = {}, NS._plan and NS._plan()
    for _, s in ipairs(plan and plan.route or {}) do
        if s.role == 1 and s.q and s.q.id and (s.kind == "pickup" or s.kind == nil) then
            local by = NS.Q and NS.Q(s.q.id, "startedBy")
            for _, n in ipairs(type(by) == "table" and by[1] or {}) do
                if n == npc then out[s.q.id] = s.q.name end
            end
        end
    end
    return out
end

local function InLog(id)
    if C_QuestLog.GetLogIndexForQuestID then return C_QuestLog.GetLogIndexForQuestID(id) ~= nil end
    return false
end

local function CheckOffered(offeredIDs, offeredNames)
    local npc = NpcID("npc")
    if not npc then return end
    local who = NS.safe(UnitName("npc")) or "That quest giver"
    local planned = PlannedFrom(npc)
    if not next(planned) then return end
    -- give auto-accept a moment, then see what's missing
    C_Timer.After(1, function()
        for id, name in pairs(planned) do
            if not offeredIDs[id] and not (name and offeredNames[name]) and not InLog(id)
                and not (C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id)) then
                NS.Print(("%s doesn't offer %s to you right now (it may need another quest first) - skipping it until you level up. /tq unskip brings it back."):format(who, name or ("quest " .. id)))
                NS.SkipQuest(id, "not offered")
            end
        end
    end)
end

local skipEv = CreateFrame("Frame")
for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL" }) do skipEv:RegisterEvent(e) end
skipEv:SetScript("OnEvent", function(_, event)
    if not NS.db then return end
    local ids, names = {}, {}
    if event == "GOSSIP_SHOW" then
        if not (C_GossipInfo and C_GossipInfo.GetAvailableQuests) then return end
        for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            if q.questID then ids[q.questID] = true end
            if q.title then names[q.title] = true end
        end
        for _, q in ipairs(C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}) do
            if q.questID then ids[q.questID] = true end
        end
    elseif event == "QUEST_GREETING" then
        for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
            local t = GetAvailableTitle and GetAvailableTitle(i)
            if t then names[t] = true end
        end
        for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
            local t = GetActiveTitle and GetActiveTitle(i)
            if t then names[t] = true end
        end
    elseif event == "QUEST_DETAIL" then
        local id = GetQuestID and GetQuestID()
        if not id or id == 0 then return end -- from an item or a party share, not an NPC
        ids[id] = true
        local t = GetTitleText and GetTitleText()
        if t then names[t] = true end
    end
    CheckOffered(ids, names)
end)
