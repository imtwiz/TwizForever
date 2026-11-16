-- TwizQuest: clicking an "Up next" step makes it Next, and it stays Next through re-plans
local f = io.open(REPO .. "/tools/wowsim/quest.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("%-%- 1%) fresh plan") - 1)
assert(loadstring(src))()
local ns = TwizQuest
local L = function(s) SIM.log[#SIM.log + 1] = s end
local function steps() local t = {} for i, s in ipairs(ns._plan().route) do if i > 3 then break end t[#t + 1] = (s.kind or s.role) .. ":" .. (s.q and s.q.name or "?") end return table.concat(t, " > ") end
ns.Replan(); SIM.Advance(12)
L("before: " .. steps())
local third = ns._plan().route[3]
ns.Promote(third)
L("clicked step 3: " .. steps() .. " | card shows: " .. tostring(TwizQuestFrame.card.title:GetText()))
ns.Replan(); SIM.Advance(12)
L("after a re-plan: " .. steps())
