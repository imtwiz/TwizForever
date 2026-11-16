-- TwizQuest: the next step's distance updates as you move (every yard)
local f = io.open(REPO .. "/tools/wowsim/quest.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("%-%- 1%) fresh plan") - 1)
assert(loadstring(src))()
local ns = TwizQuest
local L = function(s) SIM.log[#SIM.log + 1] = s end
TwizQuestFrame:Show(); ns.Replan(true); SIM.Advance(12)
local function sub() return (TwizQuestFrame.card.sub:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
L("start: " .. sub())
local first = ns._plan().route[1]
local realPos = ns.PlayerPos
local px, py, inst = realPos()
for i = 1, 3 do
  local nx, ny = first.x + 40 + i * 1.2, first.y
  ns.PlayerPos = function() return nx, ny, inst end
  SIM.Advance(0.2)
  L(("step %d: %s"):format(i, sub()))
end
