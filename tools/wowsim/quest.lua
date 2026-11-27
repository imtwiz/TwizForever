-- TwizQuest scenario with a tiny fake Questie: a town with a quest giver, a
-- vendor/repairer and a banker, two hunting areas and four quests.
-- Map coordinates 0-100 become world yards x10 on one continent (instance 0).
local REPO = REPO
local NPC = {
    [1] = { name = "Marshal Dughan", spawns = { [12] = { { 50, 50 } } }, npcFlags = 2, friendlyToFaction = "AH", minLevel = 30 },
    [2] = { name = "Brother Danil", spawns = { [12] = { { 52, 50 } } }, npcFlags = 128 + 4096, friendlyToFaction = "AH", minLevel = 30 },
    [3] = { name = "Banker Bob", spawns = { [12] = { { 49, 52 } } }, npcFlags = 131072, friendlyToFaction = "AH", minLevel = 30 },
    [4] = { name = "Farmer Far Away", spawns = { [12] = { { 95, 5 } } }, friendlyToFaction = "AH", minLevel = 10 },
    [10] = { name = "Kobold Vermin", spawns = { [12] = { { 60, 60 }, { 61, 60 }, { 60, 61 }, { 61, 61 }, { 62, 60 } } }, minLevel = 18, maxLevel = 19 },
    [11] = { name = "Defias Thug", spawns = { [12] = { { 30, 70 }, { 31, 70 }, { 30, 71 } } }, minLevel = 19, maxLevel = 20, rank = 0 },
    [12] = { name = "Hogger", spawns = { [12] = { { 20, 20 } } }, minLevel = 22, maxLevel = 22, rank = 1 },
}
local QUEST = {
    [100] = { name = "Kobold Camp Cleanup", questLevel = 19, requiredLevel = 15, startedBy = { { 1 } }, finishedBy = { { 1 } },
              objectives = { { { 10, "Kobold Vermin slain" } } }, xp = 1800 },
    [101] = { name = "The Defias", questLevel = 20, requiredLevel = 16, startedBy = { { 1 } }, finishedBy = { { 1 } },
              objectives = { { { 11, "Defias Thug slain" } } }, xp = 2000 },
    [102] = { name = "Wanted: Hogger", questLevel = 22, requiredLevel = 18, startedBy = { { 1 } }, finishedBy = { { 1 } },
              objectives = { { { 12, "Hogger slain" } } }, xp = 3000 },
    [103] = { name = "Old Gray Errand", questLevel = 10, requiredLevel = 5, startedBy = { { 1 } }, finishedBy = { { 4 } },
              objectives = { { { 11, "Defias Thug slain" } } }, xp = 100, finishedBy2 = true },
}
local DB = {
    QuestPointers = {}, NPCPointers = {},
    npcFlags = { VENDOR = 128, REPAIR = 4096, BANKER = 131072 },
    QueryQuestSingle = function(id, f) local q = QUEST[id] return q and q[f] end,
    QueryNPCSingle = function(id, f) local n = NPC[id] return n and n[f] end,
    QueryObjectSingle = function() return nil end,
    QueryItemSingle = function() return nil end,
    IsDoable = function(id) return true end,
    GetItemDroprate = function() return { 35 } end,
}
for id in pairs(QUEST) do DB.QuestPointers[id] = true end
for id in pairs(NPC) do DB.NPCPointers[id] = true end
local QuestXP = { GetQuestLogRewardXP = function(_, id) return QUEST[id] and QUEST[id].xp or 0 end }
local ZoneDB = { GetUiMapIdByAreaId = function(_, a) return 1453 end }
Questie = { started = false }  -- still loading at login; see the check below
QuestieLoader = { ImportModule = function(_, name) if name == "QuestieDB" then return DB elseif name == "ZoneDB" then return ZoneDB elseif name == "QuestXP" then return QuestXP end end }
SIM.px, SIM.py = 500, 500
local HBD = {
    GetWorldCoordinatesFromZone = function(_, x, y) return x * 1000, y * 1000, 0 end,
    GetPlayerWorldPosition = function() return SIM.px, SIM.py, 0 end,
}
LibStub = function(name) if name == "HereBeDragons-2.0" then return HBD end end
C_QuestLog.GetMaxNumQuestsCanAccept = function() return 25 end
C_QuestLog.IsComplete = function() return false end
C_QuestLog.IsFailed = function() return false end
C_QuestLog.SetSelectedQuest = function(id) SIM.calls[#SIM.calls + 1] = { "SetSelectedQuest", id } end
C_QuestLog.SetAbandonQuest = function() end
C_QuestLog.AbandonQuest = function() SIM.calls[#SIM.calls + 1] = { "AbandonQuest" } end
C_Map.SetUserWaypoint = function() end
UiMapPoint = { CreateFromCoordinates = function() return {} end }

SIM.level = 20
local ns = SIM.LoadAddon(REPO .. "/TwizQuest", "TwizQuest")
SIM.Fire("ADDON_LOADED", "TwizQuest"); SIM.Fire("PLAYER_LOGIN"); SIM.Advance(1)
-- 1.21.2: while Questie is still loading the window says so instead of staying blank
do
    SIM.Advance(2)
    local t = TwizQuestFrame and TwizQuestFrame.summary and TwizQuestFrame.summary:GetText() or ""
    SIM.log[#SIM.log + 1] = "while Questie loads: " .. t
    if not t:find("Questie is still loading", 1, true) then SIM.errors[#SIM.errors + 1] = "blank window while Questie loads: " .. t end
    Questie.started = true
end

local function show(label)
    SIM.log[#SIM.log + 1] = "=== " .. label
    local p = TwizQuestFrame and TwizQuestFrame.summary
    SIM.log[#SIM.log + 1] = "summary: " .. tostring(p and p:GetText())
    local plan = ns._plan and ns._plan()
    for i, s in ipairs(plan and plan.route or {}) do
        SIM.log[#SIM.log + 1] = ("  %d. %s %s %s%s"):format(i, s.kind or s.role, s.q and s.q.name or "?",
            s.who or s.name or "", (s.restBonus or 0) > 0 and (" (+%d rested)"):format(s.restBonus) or "")
    end
    local b = TwizQuestTargetButton
    SIM.log[#SIM.log + 1] = "target key: " .. tostring(b and b:GetAttribute("macrotext"))
end

-- 1) fresh plan, not rested, solo
SIM.Advance(10); show("solo, not rested")
-- 2) rested + grouped (Hogger is an elite: allowed in a group)
SIM.rested, SIM.group = 20000, 3
ns.Replan(); SIM.Advance(10); show("rested, in a group")
-- 3) bags full and gear breaking -> service stop
SIM.group = 1
for bag = 0, 4 do for slot = 1, 16 do if not SIM.bags[bag .. ":" .. slot] then SIM.bags[bag .. ":" .. slot] = { id = 9999, count = 1 } end end end
SIM.items[9999] = { name = "Junk", vendor = 1 }
SIM.durability = { [1] = { 10, 100 } }
ns.Replan(); SIM.Advance(10); show("bags full, gear at 10%")
-- 4) a gray quest in the log -> cleanup suggestion
SIM.quests = { { title = "Old Gray Errand", questID = 103, isHeader = false, objectives = { { type = "monster", text = "Defias Thug slain: 8/8", numRequired = 8, numFulfilled = 8, finished = true } } } }
ns.Replan(); SIM.Advance(10); show("gray quest in the log")
SlashCmdList.QUESTROUTE("cleanup")
SlashCmdList.QUESTROUTE("abandon")
if StaticPopupDialogs.TWIZQUEST_ABANDON then StaticPopupDialogs.TWIZQUEST_ABANDON.OnAccept(nil, ns._plan().drop) end
SIM.Advance(1)
