-- TwizQuest auto-accept: quest text, gossip list, greeting, shared escort, shift, full log
local f = io.open(REPO .. "/tools/wowsim/quest.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("%-%- 1%) fresh plan") - 1)
AcceptQuest = function() SIM.calls[#SIM.calls + 1] = { "AcceptQuest" } end
ConfirmAcceptQuest = function() SIM.calls[#SIM.calls + 1] = { "ConfirmAcceptQuest" } end
GetTitleText = function() return "Kobold Camp Cleanup" end
SelectAvailableQuest = function(i) SIM.calls[#SIM.calls + 1] = { "SelectAvailableQuest", i } end
GetNumAvailableQuests = function() return 2 end
C_GossipInfo = { GetAvailableQuests = function() return { { questID = 101, title = "The Defias" } } end,
                 SelectAvailableQuest = function(id) SIM.calls[#SIM.calls + 1] = { "GossipSelect", id } end }
StaticPopup_Hide = StaticPopup_Hide or function() end
assert(loadstring(src))()
local L = function(s) SIM.log[#SIM.log + 1] = s end
local function last() local c = SIM.calls[#SIM.calls] return c and (c[1] .. (c[2] and (" " .. c[2]) or "")) or "-" end
SIM.calls = {}; SIM.Fire("QUEST_DETAIL"); L("quest text -> " .. last())
SIM.calls = {}; SIM.Fire("GOSSIP_SHOW"); L("gossip -> " .. last())
SIM.calls = {}; SIM.Fire("QUEST_GREETING"); L("greeting -> " .. last())
SIM.calls = {}; SIM.Fire("QUEST_ACCEPT_CONFIRM"); L("shared escort -> " .. last())
IsShiftKeyDown = function() return true end
SIM.calls = {}; SIM.Fire("QUEST_DETAIL"); L("holding shift -> " .. last())
IsShiftKeyDown = function() return false end
C_QuestLog.GetMaxNumQuestsCanAccept = function() return #SIM.quests end
SIM.quests = { { title = "x", questID = 5, isHeader = false, objectives = {} } }
SIM.calls = {}; SIM.Fire("QUEST_DETAIL"); L("log full -> " .. last())
C_QuestLog.GetMaxNumQuestsCanAccept = function() return 25 end
SlashCmdList.QUESTROUTE("accept")
SIM.calls = {}; SIM.Fire("QUEST_DETAIL"); L("after /tq accept (off) -> " .. last())
