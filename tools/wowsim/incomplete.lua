-- TwizQuest: never "turn in" a quest that isn't done (objective it can't map, or the game saying complete too early)
local f = io.open(REPO .. "/tools/wowsim/quest.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("%-%- 1%) fresh plan") - 1)
assert(loadstring(src))()
local ns = TwizQuest
local L = function(s) SIM.log[#SIM.log + 1] = s end
SIM.complete = { [100] = true }   -- the game says Kobold Camp Cleanup is complete...
C_QuestLog.IsComplete = function(id) return SIM.complete[id] or false end
SIM.quests = {
  -- ...but one objective is still unfinished
  { title = "Kobold Camp Cleanup", questID = 100, isHeader = false, objectives = { { type = "monster", text = "Kobold Vermin slain: 6/8", numRequired = 8, numFulfilled = 6, finished = false } } },
  -- an objective Questie can't place (reputation)
  { title = "The Defias", questID = 101, isHeader = false, objectives = { { type = "reputation", text = "Earn the trust of the Brotherhood", numRequired = 1, numFulfilled = 0, finished = false } } },
}
ns.cache = nil; ns.MarkDirty(); ns.Replan(true); SIM.Advance(12)
for i, s in ipairs(ns._plan().route) do
  L(("%d. %s %s %s"):format(i, s.kind or tostring(s.role), s.q and s.q.name or "?", s.text and ("(" .. s.text .. ")") or ""))
end
