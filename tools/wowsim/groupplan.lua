-- TwizQuest party sync: Bob joins, logs are exchanged, quests shared, help stops planned
SIM.sent, SIM.inGroup, SIM.partyNames = {}, false, {}
C_ChatInfo = C_ChatInfo or {}
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ChatInfo.SendAddonMessage = function(prefix, msg, chan) SIM.sent[#SIM.sent + 1] = msg end
IsInGroup = function() return SIM.inGroup end
IsInRaid = function() return false end
UnitInParty = function() return false end   -- the game's name check: never relied on
QuestLogPushQuest = function() SIM.calls[#SIM.calls + 1] = { "QuestLogPushQuest" } end
local realUnitName = UnitName
UnitName = function(u)
  local i = u and tonumber(u:match("^party(%d)$") or "")
  if i then return SIM.partyNames[i] end
  return realUnitName(u)
end
-- run the shared TwizQuest world from quest.lua (up to its scenarios)
local f = io.open(REPO .. "/tools/wowsim/quest.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("%-%- 1%) fresh plan") - 1)
assert(loadstring(src))()
local ns = TwizQuest
SIM.complete = { [100] = true }
C_QuestLog.IsComplete = function(id) return SIM.complete[id] or false end
C_QuestLog.IsPushableQuest = function(id) return true end
SIM.quests = {
  { title = "Old Gray Errand", questID = 103, isHeader = false, objectives = { { type = "monster", text = "Defias Thug slain: 1/8", numRequired = 8, numFulfilled = 1, finished = false } } },
  { title = "Kobold Camp Cleanup", questID = 100, isHeader = false, objectives = { { type = "monster", text = "Kobold Vermin slain: 8/8", numRequired = 8, numFulfilled = 8, finished = true } } },
  { title = "The Defias", questID = 101, isHeader = false, objectives = { { type = "monster", text = "Defias Thug slain: 2/8", numRequired = 8, numFulfilled = 2, finished = false } } },
}
local function L(s) SIM.log[#SIM.log + 1] = s end
local function route(label)
  ns.cache = nil; ns.Replan(); SIM.Advance(12)
  L("=== " .. label)
  for i, s in ipairs(ns._plan().route) do
    L(("  %d. %s %s%s"):format(i, s.kind or s.role, s.q and s.q.name or "?", s.help and (" [helping " .. s.help .. ", " .. (s.need or 0) .. " kills]") or ""))
  end
  local pl = TwizQuestFrame.partyLine
  L("party line: " .. tostring(pl.__shown and pl.text:GetText() or "(hidden)"))
end

local function drops() return #(ns._plan().drop or {}) end
local function routeIds()
  local o, seen = {}, {}
  for _, st in ipairs(ns._plan().route) do if st.q and not seen[st.q.id] then seen[st.q.id] = true; o[#o + 1] = st.q.name end end
  return table.concat(o, ", ")
end
route("solo")
L(("solo: drop suggestions %d, quests in route: %s"):format(drops(), routeIds()))

-- Bob joins and syncs: he has the kobolds (behind) and Hogger
SIM.inGroup, SIM.partyNames = true, { "Bob" }
SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.Advance(3)
local function fromBob(m) SIM.Fire("CHAT_MSG_ADDON", "TWZQ", m, "PARTY", "Bob-Realm") end
fromBob("B|1|20"); fromBob("Q|100|0|m3/8"); fromBob("Q|101|0|m1/8"); fromBob("E"); fromBob("X|20|100|9000|0|5000")
SIM.Advance(3)
route("synced with Bob")
L(("synced: drop suggestions %d, quests in route: %s"):format(drops(), routeIds()))
SlashCmdList.QUESTROUTE("cleanup")

-- click Group
SIM.sent = {}
SIM.calls = {}
TwizQuestFrame.groupBtn:Click(); SIM.Advance(12)
L("group button text: " .. TwizQuestFrame.groupBtn:GetText())
L("summary: " .. (TwizQuestFrame.summary:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
local g
for _, m in ipairs(SIM.sent) do if m:match("^G|") then g = m end end
L("sent to party: " .. tostring(g))
L("group route: " .. routeIds())
-- back to solo tells the party
SIM.sent = {}
TwizQuestFrame.groupBtn:Click(); SIM.Advance(12)
local cleared
for _, m in ipairs(SIM.sent) do if m == "G|" then cleared = true end end
L("solo: told party plan ended = " .. tostring(cleared) .. ", button " .. TwizQuestFrame.groupBtn:GetText())

-- Bob starts a group plan: we follow it, and keep all our quests
fromBob("G|101,100"); SIM.Advance(12)
L("following: groupPlan from " .. tostring(ns.groupPlan and ns.groupPlan.from) .. ", route: " .. routeIds() .. ", drops " .. drops())
fromBob("G|"); SIM.Advance(12)
L("Bob ended it: groupMode " .. tostring(ns.groupMode))
-- 1.19.1: Solo while Bob runs a plan, then Group again -> back on Bob's plan (no second plan)
fromBob("G|101,100"); SIM.Advance(12)
L("Bob's plan arrives while we're on Solo: following " .. tostring(ns.groupPlan and ns.groupPlan.from))
SIM.sent = {}
TwizQuestFrame.groupToggle.buttons[2]:Click(); SIM.Advance(12)
local ours
for _, m in ipairs(SIM.sent) do if m:match("^G|%d") then ours = m end end
L("Group again: groupMode " .. tostring(ns.groupMode) .. ", following " .. tostring(ns.groupPlan and ns.groupPlan.from) .. ", sent our own plan " .. tostring(ours))
assert(ns.groupMode and ns.groupPlan and ns.groupPlan.from == "Bob" and not ours)
TwizQuestFrame.groupToggle.buttons[1]:Click(); SIM.Advance(12)
L("Solo again: groupMode " .. tostring(ns.groupMode) .. ", toggle shown " .. tostring(TwizQuestFrame.groupToggle.__shown))
assert(not ns.groupMode and TwizQuestFrame.groupToggle.__shown)
TwizQuestFrame.groupToggle.buttons[2]:Click(); SIM.Advance(12)
L("and Group once more: following " .. tostring(ns.groupPlan and ns.groupPlan.from))
assert(ns.groupMode)
