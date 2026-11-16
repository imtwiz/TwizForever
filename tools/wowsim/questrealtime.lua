-- TwizQuest: next step comes up right away; a plan already running can't bring back a finished step
local f = io.open(REPO .. "/tools/wowsim/quest.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("%-%- 1%) fresh plan") - 1)
assert(loadstring(src))()
local ns = TwizQuest
local L = function(s) SIM.log[#SIM.log + 1] = s end
local function steps() local t = {} for i, s in ipairs(ns._plan().route) do if i > 4 then break end t[#t + 1] = (s.kind or s.role) .. ":" .. (s.q and s.q.name or "?") end return table.concat(t, " > ") end
ns.Replan(); SIM.Advance(12)
L("start: " .. steps())
local first = ns._plan().route[1]
-- start a plan, then accept the first quest while it's still running
ns.MarkDirty(); ns.Plan(true)
L("planning: " .. tostring(ns.IsPlanning()))
SIM.quests[#SIM.quests + 1] = { title = first.q.name, questID = first.q.id, isHeader = false, objectives = { { type = "monster", text = "x: 0/8", numRequired = 8, numFulfilled = 0, finished = false } } }
SIM.Fire("QUEST_ACCEPTED", first.q.id)
L("right after accepting: " .. steps())
SIM.Advance(0.2)
SIM.Advance(3)
local back = false
for _, s in ipairs(ns._plan().route) do if s.q and s.q.id == first.q.id and s.role == 1 then back = true end end
L("pickup of " .. first.q.name .. " came back after the old plan finished: " .. tostring(back))
L("now: " .. steps())
