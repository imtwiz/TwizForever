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

SIM.leader = nil
UnitIsGroupLeader = function(u) return SIM.leader == u end
local function fromBob(m) SIM.Fire("CHAT_MSG_ADDON", "TWZQ", m, "PARTY", "Bob-Realm") end
local function sentG() for _, m in ipairs(SIM.sent) do if m:match("^G|") then return m end end end
-- 1) Bob (sorts first, no leader) plans; we wait, then follow his plan
SIM.inGroup, SIM.partyNames = true, { "Bob" }
SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.Advance(3)
SIM.sent = {}
fromBob("B|1|20"); fromBob("Q|100|0|m3/8"); fromBob("E"); SIM.Advance(15)
L("no leader, Bob sorts first: I sent a plan? " .. tostring((sentG())) .. ", groupMode " .. tostring(ns.groupMode))
fromBob("G|101,100"); SIM.Advance(12)
L("Bob's plan arrived: following " .. tostring(ns.groupPlan and ns.groupPlan.from))
-- 2) quests are never removed while synced
local shown
local realShow = StaticPopup_Show
StaticPopup_Show = function(w) shown = w end
SlashCmdList.QUESTROUTE("dropall")
L("Drop All while synced -> popup " .. tostring(shown) .. ", button shown " .. tostring(TwizQuestFrame.dropAll.__shown))
SIM.calls = {}
StaticPopupDialogs.TWIZQUEST_ABANDON_ALL.OnAccept(); SIM.Advance(1)
local ab = 0 for _, c in ipairs(SIM.calls) do if c[1] == "AbandonQuest" then ab = ab + 1 end end
L("even if the popup is accepted: abandoned " .. ab)
StaticPopup_Show = realShow
-- 3) Solo: stays solo, ignores further plans
TwizQuestFrame.groupBtn:Click(); SIM.Advance(12)
fromBob("G|101,100"); SIM.Advance(12)
L("after Solo, Bob re-sends: groupMode " .. tostring(ns.groupMode))
-- 4) leave and regroup as party leader: we plan automatically and send it
SIM.inGroup, SIM.partyNames = false, {}
SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.Advance(2)
SIM.inGroup, SIM.partyNames, SIM.leader = true, { "Bob" }, "player"
SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.Advance(3)
SIM.sent = {}
fromBob("B|1|20"); fromBob("Q|100|0|m3/8"); fromBob("E"); SIM.Advance(15)
L("regrouped as leader: groupMode " .. tostring(ns.groupMode) .. ", sent " .. tostring((sentG())))
L("summary: " .. (TwizQuestFrame.summary:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):sub(1, 60))
