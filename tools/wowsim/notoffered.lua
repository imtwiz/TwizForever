-- TwizQuest: a quest the giver doesn't actually offer gets skipped (until level up / unskip); right-click skip
local f = io.open(REPO .. "/tools/wowsim/quest.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("%-%- 1%) fresh plan") - 1)
assert(loadstring(src))()
local ns = TwizQuest
local L = function(s) SIM.log[#SIM.log + 1] = s end
strsplit = strsplit or function(sep, s) local t = {} for p in (s .. sep):gmatch("(.-)%" .. sep) do t[#t + 1] = p end return unpack(t) end
SIM.npcGUID = nil
UnitGUID = function(u) if u == "npc" then return SIM.npcGUID end return "Player-1-0000" end
local realUN = UnitName
UnitName = function(u) if u == "npc" then return "Captain Stoutfist" end return realUN(u) end
C_GossipInfo = C_GossipInfo or {}
SIM.offered = {}
C_GossipInfo.GetAvailableQuests = function() return SIM.offered end
C_GossipInfo.GetActiveQuests = function() return {} end
C_GossipInfo.SelectAvailableQuest = function() end
local function pickups()
  ns.cache = nil; ns.MarkDirty(); ns.Replan(true); SIM.Advance(12)
  local o, q = {}, {}
  for _, s in ipairs(ns._plan().route) do if s.kind == "pickup" then o[#o + 1] = s.q.name end if s.q and not q[s.q.name] then q[s.q.name] = true end end
  local all = {} for n in pairs(q) do all[#all + 1] = n end table.sort(all)
  return table.concat(o, ", ") .. "  | quests: " .. table.concat(all, ", ")
end
L("pickups planned: " .. pickups())
-- talk to the giver (npc id 1): only Kobold Camp Cleanup is on offer
SIM.npcGUID = "Creature-0-0-0-0-1-0000"
SIM.offered = { { questID = 100, title = "Kobold Camp Cleanup" } }
SIM.Fire("GOSSIP_SHOW"); SIM.Advance(2)
L("after talking to the giver: " .. pickups())
-- right-click skip of another pickup
local rows = ns._upNextRows
for _, r in ipairs(rows) do
  if r.__shown and r.step and r.step.q and r.step.kind ~= "service" then
    L("right-click skip: " .. r.step.q.name); r.__scripts.OnClick(r, "RightButton"); break
  end
end
SIM.Advance(1)
L("after right-click: " .. pickups())
SlashCmdList.QUESTROUTE("unskip"); SIM.Advance(1)
L("after /tq unskip: " .. pickups())
