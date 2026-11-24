-- TwizQuest 1.20.0: keyboard dialogue and the flight timer
local taxi = { { "Astranaar, Ashenvale", "CURRENT" }, { "Auberdine, Darkshore", "REACHABLE" } }
NumTaxiNodes = function() return #taxi end
TaxiNodeName = function(i) return taxi[i] and taxi[i][1] end
TaxiNodeGetType = function(i) return taxi[i] and taxi[i][2] end
TakeTaxiNode = function(i) end
local onTaxi = false
UnitOnTaxi = function() return onTaxi end
local f = io.open(REPO .. "/tools/wowsim/quest.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("%-%- 1%) fresh plan") - 1)
assert(loadstring(src))()
local ns = TwizQuest
local L = function(s) SIM.log[#SIM.log + 1] = s end
local did = {}
C_GossipInfo = {
  GetAvailableQuests = function() return { { questID = 501, title = "New One" } } end,
  GetActiveQuests = function() return { { questID = 400, title = "Done One", isComplete = true } } end,
  GetOptions = function() return { { gossipOptionID = 77, name = "Train me", orderIndex = 0 } } end,
  SelectAvailableQuest = function(id) did[#did + 1] = "available " .. id end,
  SelectActiveQuest = function(id) did[#did + 1] = "active " .. id end,
  SelectOption = function(id) did[#did + 1] = "option " .. id end,
}
AcceptQuest = function() did[#did + 1] = "accept" end
IsQuestCompletable = function() return true end
CompleteQuest = function() did[#did + 1] = "complete" end
local choices = 0
GetNumQuestChoices = function() return choices end
GetQuestReward = function(n) did[#did + 1] = "reward " .. tostring(n) end
IsShiftKeyDown = function() return false end
ns.db.autoAccept = false -- only the keys act here
local keys = TwizQuestTalkKeys
local function press(k) keys:GetScript("OnKeyDown")(keys, k) end

SIM.Fire("GOSSIP_SHOW"); press("SPACE")
L("gossip Space: " .. tostring(did[#did]) .. "  (a finished quest to turn in comes first)")
assert(did[#did] == "active 400")
press("1"); press("3"); press("W")
L("gossip 1 / 3 / W: " .. did[#did - 1] .. ", " .. did[#did] .. ", W passed through")
assert(did[#did - 1] == "available 501" and did[#did] == "option 77")
SIM.Fire("QUEST_DETAIL"); press("SPACE"); L("quest text Space: " .. did[#did]); assert(did[#did] == "accept" or did[#did - 1] == "accept")
SIM.Fire("QUEST_PROGRESS"); press("SPACE"); L("turn-in Space: " .. did[#did]); assert(did[#did] == "complete")
-- 1.21.0: Space takes the best reward: a real upgrade for a druid (leather), else the best seller
UnitClass = function() return "druid", "DRUID" end
UnitLevel = function() return 25 end
local rewards = { "item:5001", "item:5002", "item:5003" }
GetQuestItemLink = function(kind, i) return rewards[i] end
local realGII2 = GetItemInfo
GetItemInfo = function(x)
  if x == "item:5001" then return "Cloth Robe", nil, nil, 24, 20, "Armor", "Cloth", 1, "INVTYPE_CHEST", nil, 80 end
  if x == "item:5002" then return "Leather Vest", nil, nil, 22, 20, "Armor", "Leather", 1, "INVTYPE_CHEST", nil, 30 end
  if x == "item:5003" then return "Fancy Plate", nil, nil, 30, 20, "Armor", "Plate", 1, "INVTYPE_CHEST", nil, 900 end
  if x == "item:4000" then return "Old Vest", nil, nil, 15, 10, "Armor", "Leather", 1, "INVTYPE_CHEST", nil, 5 end
  return realGII2 and realGII2(x)
end
GetInventoryItemLink = function(u, slot) return slot == 5 and "item:4000" or nil end
choices = 3; SIM.Fire("QUEST_COMPLETE"); local n0 = #did; press("SPACE")
L("reward screen: Space -> " .. did[#did] .. "  (Leather Vest: the upgrade a druid can wear)")
assert(did[#did] == "reward 2")
GetInventoryItemLink = function() return nil end
rewards = { "item:5001", "item:5003" }; choices = 2
GetInventoryItemLink = function(u, slot) return slot == 5 and "item:5002" or nil end -- wearing better already
local best, why = ns.BestReward()
L("no upgrade: best = " .. tostring(best) .. " (" .. tostring(why) .. ")")
assert(best == 2 and why == "sells best")
press("2"); assert(did[#did] == "reward 2")
SIM.Fire("QUEST_FINISHED"); local n1 = #did; press("SPACE"); assert(#did == n1, "closed: keys do nothing")
ns.db.talkKeys = false; SIM.Fire("GOSSIP_SHOW"); press("SPACE"); assert(#did == n1, "/tq talk off")
ns.db.talkKeys = true
L("closed / turned off: keys pass through")

-- flight timer: first flight is timed, the second counts down
ns._flight.Chose(2)
onTaxi = true; SIM.Advance(1); SIM.Advance(95); onTaxi = false; SIM.Advance(1)
local t = ns.FlightTime("Astranaar, Ashenvale", "Auberdine, Darkshore")
L("timed Astranaar -> Auberdine: " .. tostring(t) .. "s")
assert(t and t >= 94 and t <= 98)
ns._flight.Chose(2); onTaxi = true; SIM.Advance(1); SIM.Advance(30)
L("second flight bar: " .. tostring(TwizQuestFlightBar and TwizQuestFlightBar.text:GetText()))
assert(TwizQuestFlightBar.text:GetText():find("left"))
onTaxi = false; SIM.Advance(1)
SlashCmdList.QUESTROUTE("flights list")
