-- TwizQuest keyboard dialogue (1.20.0) - like DialogKey, built in.
-- While an NPC's dialogue is open (out of combat):
--   Space  = the obvious next step: accept the quest, continue, complete it, take the reward,
--            or pick the first quest / option in a gossip menu
--   1 - 9  = pick that line: in a gossip menu quests come first (new, then in progress), then
--            the talk options; on a reward screen, the reward in that slot
-- Every other key works as usual. Hold Shift to type normally. /tq talk turns it on or off.
local ADDON, NS = ...

local open           -- which dialogue is up: "gossip", "greeting", "detail", "progress", "complete"
local key = CreateFrame("Frame", "TwizQuestTalkKeys", UIParent)
key:SetAllPoints(UIParent)
key:EnableKeyboard(false)
key:SetFrameStrata("TOOLTIP")
key:Hide()

local function On() return NS.db and NS.db.talkKeys ~= false end

-- gossip lines in the order they're numbered: new quests, quests in progress, talk options
local function GossipLines()
    local lines = {}
    if not C_GossipInfo then return lines end
    for _, q in ipairs(C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests() or {}) do
        lines[#lines + 1] = { kind = "available", q = q }
    end
    for _, q in ipairs(C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}) do
        lines[#lines + 1] = { kind = "active", q = q }
    end
    local opts = C_GossipInfo.GetOptions and C_GossipInfo.GetOptions() or {}
    table.sort(opts, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
    for _, o in ipairs(opts) do lines[#lines + 1] = { kind = "option", o = o } end
    return lines
end
NS.GossipLines = GossipLines

local function PickGossip(line)
    if not line then return false end
    if line.kind == "available" and line.q.questID then C_GossipInfo.SelectAvailableQuest(line.q.questID)
    elseif line.kind == "active" and line.q.questID then C_GossipInfo.SelectActiveQuest(line.q.questID)
    elseif line.kind == "option" and line.o.gossipOptionID then C_GossipInfo.SelectOption(line.o.gossipOptionID)
    else return false end
    return true
end

-- the old-style quest greeting (several quests, no gossip): quests in progress are listed first
local function GreetingPick(n)
    local active = GetNumActiveQuests and GetNumActiveQuests() or 0
    local avail = GetNumAvailableQuests and GetNumAvailableQuests() or 0
    if n <= active then SelectActiveQuest(n); return true end
    if n - active <= avail then SelectAvailableQuest(n - active); return true end
    return false
end

-- Space: the obvious next step
local function Next()
    if open == "detail" then AcceptQuest(); return true end
    if open == "progress" then
        if IsQuestCompletable and IsQuestCompletable() then CompleteQuest(); return true end
        return false
    end
    if open == "complete" then
        local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
        if choices <= 1 then GetQuestReward(choices == 1 and 1 or nil); return true end
        -- 1.21.0: the best one (an upgrade for your class, else the best seller)
        local best = NS.BestReward and NS.BestReward()
        if best then GetQuestReward(best); return true end
        NS.Print(("pick a reward: press 1-%d."):format(choices))
        return true
    end
    if open == "gossip" then
        local lines = GossipLines()
        -- a finished quest to turn in first, then a new quest, then the first line
        for _, l in ipairs(lines) do if l.kind == "active" and l.q.isComplete then return PickGossip(l) end end
        for _, l in ipairs(lines) do if l.kind == "available" then return PickGossip(l) end end
        return PickGossip(lines[1])
    end
    if open == "greeting" then return GreetingPick(1) end
    return false
end

local function Number(n)
    if open == "gossip" then return PickGossip(GossipLines()[n]) end
    if open == "greeting" then return GreetingPick(n) end
    if open == "complete" then
        local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
        if n <= choices then GetQuestReward(n); return true end
    end
    return false
end

local NUM = { ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9,
    NUMPAD1 = 1, NUMPAD2 = 2, NUMPAD3 = 3, NUMPAD4 = 4, NUMPAD5 = 5, NUMPAD6 = 6, NUMPAD7 = 7, NUMPAD8 = 8, NUMPAD9 = 9 }

key:SetScript("OnKeyDown", function(self, k)
    local handled = false
    if open and On() and not IsShiftKeyDown() and not InCombatLockdown()
        and not (GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()) then
        local ok, res
        if k == "SPACE" then ok, res = pcall(Next)
        elseif NUM[k] then ok, res = pcall(Number, NUM[k]) end
        handled = ok and res or false
    end
    -- let every other key through (movement, spells, chat...)
    if not InCombatLockdown() and self.SetPropagateKeyboardInput then
        self:SetPropagateKeyboardInput(not handled)
        -- and straight back to letting keys through, so nothing is ever left swallowed
        if handled and C_Timer and C_Timer.After then
            C_Timer.After(0, function() if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end end)
        end
    end
end)

local function Arm()
    if open and On() and not InCombatLockdown() then
        key:Show(); key:EnableKeyboard(true)
        if key.SetPropagateKeyboardInput then key:SetPropagateKeyboardInput(true) end
    elseif not InCombatLockdown() then
        key:EnableKeyboard(false); key:Hide()
    end
end
NS.TalkArm = Arm

local ev = CreateFrame("Frame")
local OPEN = { GOSSIP_SHOW = "gossip", QUEST_GREETING = "greeting", QUEST_DETAIL = "detail",
    QUEST_PROGRESS = "progress", QUEST_COMPLETE = "complete" }
for e in pairs(OPEN) do ev:RegisterEvent(e) end
for _, e in ipairs({ "GOSSIP_CLOSED", "QUEST_FINISHED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", function(_, event)
    if OPEN[event] then open = OPEN[event]
    elseif event == "GOSSIP_CLOSED" or event == "QUEST_FINISHED" then open = nil end
    if event == "PLAYER_REGEN_DISABLED" then pcall(key.EnableKeyboard, key, false); return end -- never in combat
    Arm()
end)

function NS.TalkCmd()
    NS.db.talkKeys = NS.db.talkKeys == false
    NS.Print("keyboard dialogue " .. (NS.db.talkKeys and "on: Space = next step, 1-9 = pick a line (hold Shift to type normally)" or "off"))
    Arm()
end
NS._talk = { Next = Next, Number = Number, SetOpen = function(v) open = v end }
