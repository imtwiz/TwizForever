-- TwizQuest: /tq works, minimap button toggles the window and hides on request
local f = io.open(REPO .. "/tools/wowsim/quest.lua"); local src = f:read("*a"); f:close()
Minimap = Minimap or CreateFrame("Frame", "Minimap", UIParent)
if Minimap.SetSize then Minimap:SetSize(140, 140) end
src = src:sub(1, src:find("%-%- 1%) fresh plan") - 1)
assert(loadstring(src))()
SIM.Advance(1)
local L = function(s) SIM.log[#SIM.log + 1] = s end
L("slash /tq registered: " .. tostring(SLASH_QUESTROUTE1) .. ", old " .. tostring(SLASH_QUESTROUTE3))
local b = TwizQuestMinimapButton
L("minimap button exists: " .. tostring(b ~= nil) .. ", shown " .. tostring(b and b.__shown))
local before = TwizQuestFrame.__shown
b:Click("LeftButton"); SIM.Advance(0.2)
L(("left-click toggles window: %s -> %s"):format(tostring(before), tostring(TwizQuestFrame.__shown)))
SlashCmdList.QUESTROUTE("minimap"); SIM.Advance(0.1)
L("after /tq minimap: shown " .. tostring(b.__shown))
SlashCmdList.QUESTROUTE("minimap"); SIM.Advance(0.1)
L("again: shown " .. tostring(b.__shown))
