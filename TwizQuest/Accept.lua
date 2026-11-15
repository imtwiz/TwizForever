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
