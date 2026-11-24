-- TwizQuest 1.21.0: hearthstone and timed flights in the plan
local f = io.open(REPO .. "/tools/wowsim/quest.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("%-%- 1%) fresh plan") - 1)
-- a class trainer for the trainer-stop test
src = src:gsub('(%[4%] = { name = "Farmer Far Away".-},\n)', '%1    [5] = { name = "Kal", subName = "Druid Trainer", spawns = { [12] = { { 60, 60 } } }, npcFlags = 16 + 32, friendlyToFaction = "AH", minLevel = 30 },\n', 1)
assert(src:find("Druid Trainer"), "trainer injected")
UnitClass = function() return "Druid", "DRUID" end
assert(loadstring(src))()
local ns = TwizQuest
local L = function(s) SIM.log[#SIM.log + 1] = s end
local function plan() ns.cache = nil; ns.Replan(); SIM.Advance(12); return ns._plan().route end
local r = plan()
local px, py, inst = ns.PlayerPos()
local far, fd = nil, 0
for _, s in ipairs(r) do local d = ns.Dist(px, py, s.x, s.y); if d > fd then far, fd = s, d end end
L(("plan on foot: %d steps, farthest %d yd away, ETA %s"):format(#r, fd, ns.FormatTime(r[#r].eta)))
local etaWalk = r[#r].eta
-- hearth set right next to the farthest step, off cooldown
GetBindLocation = function() return "Far Inn" end
ns.db.bind = { name = "Far Inn", x = far.x + 5, y = far.y + 5, inst = inst }
GetItemCount = function(id) return id == 6948 and 1 or 0 end
C_Container = C_Container or {}
C_Container.GetItemCooldown = function() return 0, 0, 1 end
r = plan()
local vias = {}
for i, s in ipairs(r) do if s.via then vias[#vias + 1] = i .. ": " .. s.via end end
L("with hearth ready: " .. (#vias > 0 and table.concat(vias, "; ") or "no hearth used") .. ", ETA " .. ns.FormatTime(r[#r].eta))
local t, via = ns.TravelVia({ x = px, y = py, isStart = true }, far, ns.TravelTime(fd))
L(("leg to the farthest step: on foot %s, best %s via %s"):format(ns.FormatTime(ns.TravelTime(fd)), ns.FormatTime(t), tostring(via)))
assert(via == "hearth to Far Inn")
-- a slow walker (this test world is small): the whole plan starts with the hearth
ns.db.learn.runSpeed = 1
r = plan()
L("slow walker, first step: " .. tostring(r[1].q and r[1].q.name) .. " via " .. tostring(r[1].via))
-- (whether the router puts the far step first depends on the rest of the plan)
ns.db.learn.runSpeed = 7
-- on cooldown: back on foot
C_Container.GetItemCooldown = function() return GetTime(), 3600, 1 end
r = plan()
L("hearth on cooldown: first step via " .. tostring(r[1].via))
assert(not (r[1].via or ""):find("hearth"))
-- a timed flight from right here to beside the farthest step
ns.db.taxi = { ["Here Post"] = { x = px + 3, y = py + 3, inst = inst }, ["There Post"] = { x = far.x - 5, y = far.y - 5, inst = inst } }
ns.db.flights = { ["Here Post -> There Post"] = 20 }
r = plan()
local fly
for _, s in ipairs(r) do if s.via and s.via:find("^fly") then fly = s.via end end
L("with a 20s flight known: " .. tostring(fly))
assert(fly == "fly Here Post to There Post")
-- quest item button: step 1's quest has an item you use
local q1 = r[1].q and r[1].q.id
C_QuestLog.GetLogIndexForQuestID = function(id) return id == q1 and 3 or nil end
GetQuestLogSpecialItemInfo = function(idx) if idx == 3 then return "item:9999:0", "Interface\\Icons\\INV_Misc_Bag_10" end end
ns.UpdateItemButton()
L(("item button for quest %s: item=%s shown=%s"):format(tostring(q1), tostring(TwizQuestItemButton:GetAttribute("item")), tostring(TwizQuestItemButton:IsShown())))
assert(TwizQuestItemButton:GetAttribute("item") == "item:9999:0" and TwizQuestItemButton:IsShown())
GetQuestLogSpecialItemInfo = function() return nil end
ns.UpdateItemButton()
assert(not TwizQuestItemButton:IsShown())
L("no item: button hidden")

-- class trainer stop after an even level
ns.db.service = false
C_Container.GetItemCooldown = function() return GetTime(), 3600, 1 end
SIM.Fire("PLAYER_LEVEL_UP", 26)
r = plan()
local tr
for i, st in ipairs(r) do if st.kind == "trainer" then tr = i .. ": " .. tostring(st.who) end end
L("after dinging 26: trainer step " .. tostring(tr))
assert(tr and tr:find("Kal"))
SIM.Fire("TRAINER_SHOW")
r = plan()
tr = nil
for _, st in ipairs(r) do if st.kind == "trainer" then tr = true end end
L("after visiting the trainer: trainer step " .. tostring(tr))
assert(not tr)
-- minimap line: dots placed toward step 1
local placed = {}
local fakePins = { AddMinimapIconWorld = function(_, ref, dot, i, x, y) placed[dot] = { x, y } end,
  RemoveMinimapIcon = function(_, ref, dot) placed[dot] = nil end }
local realLS = LibStub
LibStub = function(name, silent) if name == "HereBeDragons-Pins-2.0" then return fakePins end return realLS(name, silent) end
r[1].x, r[1].y = px + 100, py   -- step 1 100 yards away
ns.DrawMiniLine()
local n = 0; for _ in pairs(placed) do n = n + 1 end
assert(n == 5, "100 yd / 18 yd spacing = 5 dots")
L(("minimap line: %d dots toward %s (%d yd)"):format(n, tostring(r[1].q and r[1].q.name), ns.Dist(px, py, r[1].x, r[1].y)))
SlashCmdList.QUESTROUTE("line")
n = 0; for _ in pairs(placed) do n = n + 1 end
L("line off: " .. n .. " dots")
assert(n == 0)
