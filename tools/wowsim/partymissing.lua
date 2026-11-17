-- TwizQuest: "your party is missing N of these quests" once per new missing quest, not every re-plan
local f = io.open(REPO .. "/tools/wowsim/quest.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("%-%- 1%) fresh plan") - 1)
assert(loadstring(src))()
local ns = TwizQuest
local L = function(s) SIM.log[#SIM.log + 1] = s end
local said = 0
local oldPrint = ns.Print
ns.Print = function(m) if tostring(m):find("missing") then said = said + 1 end end
local missing = { { id = 100, who = "Lute" } }
ns.PartyStatus = function() return { members = {}, missing = missing, theyHave = {}, behind = {}, ready = {}, noAddon = {}, same = {}, sameSome = 0 } end
for i = 1, 5 do ns.SendGroupPlan({}); SIM.Advance(2) end
L("5 re-plans, same missing quest: said " .. said .. " time(s)")
missing[#missing + 1] = { id = 101, who = "Lute" }
ns.SendGroupPlan({}); SIM.Advance(2); ns.SendGroupPlan({}); SIM.Advance(2)
L("a new missing quest, 2 re-plans: said " .. said .. " time(s) total")
ns.Print = oldPrint
