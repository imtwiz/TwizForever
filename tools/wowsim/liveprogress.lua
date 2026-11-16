-- TwizQuest: counts follow the quest log right away (in combat too), finished objectives drop off
local f = io.open(REPO .. "/tools/wowsim/quest.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("%-%- 1%) fresh plan") - 1)
assert(loadstring(src))()
local ns = TwizQuest
local L = function(s) SIM.log[#SIM.log + 1] = s end
SIM.complete = {}
C_QuestLog.IsComplete = function(id) return SIM.complete[id] or false end
SIM.quests = {
  { title = "Kobold Camp Cleanup", questID = 100, isHeader = false, objectives = { { type = "monster", text = "Kobold Vermin slain: 2/8", numRequired = 8, numFulfilled = 2, finished = false } } },
  { title = "The Defias", questID = 101, isHeader = false, objectives = { { type = "reputation", text = "0/12 Perfect Razormaw Egg", numRequired = 12, numFulfilled = 0, finished = false } } },
}
ns.cache = nil; ns.MarkDirty(); ns.Replan(true); SIM.Advance(12)
local function show(tag)
  local t = {}
  for i, s in ipairs(ns._plan().route) do
    if s.role == 2 then t[#t + 1] = (s.kind == "todo" and s.text) or (s.kind .. " need " .. tostring(s.need) .. " key " .. tostring(s.key)) end
  end
  L(tag .. ": " .. table.concat(t, " | "))
end
show("start")
InCombatLockdown = function() return true end
SIM.quests[1].objectives[1].numFulfilled = 5; SIM.quests[1].objectives[1].text = "Kobold Vermin slain: 5/8"
SIM.quests[2].objectives[1].numFulfilled = 3; SIM.quests[2].objectives[1].text = "3/12 Perfect Razormaw Egg"
SIM.Fire("QUEST_LOG_UPDATE"); SIM.Advance(1)
show("in combat after kills/loot")
SIM.quests[2].objectives[1].numFulfilled = 12; SIM.quests[2].objectives[1].finished = true
SIM.Fire("QUEST_LOG_UPDATE"); SIM.Advance(1)
show("eggs done")
SIM.complete[100] = true; SIM.quests[1].objectives[1].finished = true
SIM.Fire("UNIT_QUEST_LOG_CHANGED", "player"); SIM.Advance(1)
show("kobolds done")
