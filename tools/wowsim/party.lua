-- TwizQuest party sync: Bob joins, logs are exchanged, quests shared, help stops planned
SIM.sent, SIM.inGroup, SIM.partyNames = {}, false, {}
C_ChatInfo = C_ChatInfo or {}
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ChatInfo.SendAddonMessage = function(prefix, msg, chan) SIM.sent[#SIM.sent + 1] = msg end
IsInGroup = function() return SIM.inGroup end
IsInRaid = function() return false end
UnitInParty = function(n) for _, v in ipairs(SIM.partyNames) do if v == n then return true end end return false end
Ambiguate = function(n) return (n:gsub("%-.*", "")) end
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
route("solo")

-- Bob joins
SIM.inGroup, SIM.partyNames = true, { "Bob" }
SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.Advance(3)
L("I sent: " .. table.concat(SIM.sent, "  ||  "))
local function fromBob(m) SIM.Fire("CHAT_MSG_ADDON", "TWZQ", m, "PARTY", "Bob-Realm") end
fromBob("H|1|19"); fromBob("B|1|19")
fromBob("Q|100|0|m3/8")      -- Bob is behind on the kobolds
fromBob("Q|102|0|m0/1")      -- Bob has Hogger, I don't
fromBob("E"); SIM.Advance(5)
local pushes, selected = 0, {}
for _, c in ipairs(SIM.calls) do
  if c[1] == "QuestLogPushQuest" then pushes = pushes + 1 end
  if c[1] == "SetSelectedQuest" then selected[#selected + 1] = c[2] end
end
L(("auto-share: %d push(es), quest(s) %s"):format(pushes, table.concat(selected, ",")))
fromBob("N|100|Kill Kobold Vermin")
route("Bob synced, behind on kobolds")

-- XP bars: Bob reports his XP, then levels up
fromBob("X|19|4200|9000|1500|5400"); SIM.Advance(1)
local function bars()
  local out = {}
  for i, r in ipairs(TwizQuestFrame.xpRows) do
    if r.__shown then out[#out + 1] = (r.name:GetText() or "") .. " [" .. (r.text:GetText() or "") .. "] " .. (r.right:GetText() or "") end
  end
  return table.concat(out, "  ||  ")
end
L("xp bars: " .. bars())
fromBob("X|20|300|9800|0|5600"); SIM.Advance(1)
L("after Bob levels: " .. bars())
-- Bob finishes the kobolds -> help stop goes away, ready to turn in together
fromBob("Q|100|1|m8/8"); SIM.Advance(1)
route("Bob caught up")
local st = ns.PartyStatus()
L(("status: members %d, missing %d, behind %d, ready %d, theyHave %d"):format(#st.members, #st.missing, #st.behind, #st.ready, #st.theyHave))

-- my progress changes -> only that quest is re-sent
SIM.sent = {}
SIM.quests[2].objectives[1].numFulfilled = 5
SIM.Fire("QUEST_LOG_UPDATE"); SIM.Advance(2)
L("after my kill: sent " .. table.concat(SIM.sent, "  ||  "))
-- Bob leaves
SIM.inGroup, SIM.partyNames = false, {}
SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.Advance(1)
L("after Bob left: party entries " .. ns.Count(ns.party))
