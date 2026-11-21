-- TwizQuest: share only the quests for the zone you're in (inside a dungeon: only that dungeon's)
local f = io.open(REPO .. "/tools/wowsim/quest.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("%-%- 1%) fresh plan") - 1)
assert(loadstring(src))()
local ns = TwizQuest
local L = function(s) SIM.log[#SIM.log + 1] = s end
IsInGroup = function() return true end
GetNumGroupMembers = function() return 2 end
local log = {
  { title = "Wetlands", isHeader = true },
  { title = "Apprentice's Duties", questID = 201 }, { title = "In Search of The Excavation Team", questID = 202 },
  { title = "Razorfen Kraul", isHeader = true },
  { title = "Blueleaf Tubers", questID = 301 }, { title = "Mortality Wanes", questID = 302 },
  { title = "The Barrens", isHeader = true },
  { title = "Raptor Horns", questID = 401 },
}
C_QuestLog.GetNumQuestLogEntries = function() return #log end
C_QuestLog.GetInfo = function(i) return log[i] end
C_QuestLog.IsPushableQuest = function(id) return id ~= 202 end
ns.GroupHasAll = function() return false end
local pushed = {}
C_QuestLog.SetSelectedQuest = function(id) pushed[#pushed + 1] = id end
QuestLogPushQuest = function() end
InCombatLockdown = function() return false end
local said = {} local op = ns.Print; ns.Print = function(m) said[#said + 1] = m end
IsInInstance = function() return false end
GetRealZoneText = function() return "Wetlands" end
ns.ShareZoneCmd(); SIM.Advance(3)
L("in Wetlands: shared " .. table.concat(pushed, ",") .. " | " .. tostring(said[#said]))
pushed = {}
IsInInstance = function() return true, "party" end
GetInstanceInfo = function() return "Razorfen Kraul", "party" end
ns.ShareZoneCmd(); SIM.Advance(3)
L("inside RFK: shared " .. table.concat(pushed, ",") .. " | " .. tostring(said[#said]))
ns.Print = op
