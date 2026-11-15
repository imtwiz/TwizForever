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

local function pushes()
  local o = {}
  for _, c in ipairs(SIM.calls) do if c[1] == "SetSelectedQuest" then o[#o + 1] = c[2] end end
  local n = 0 for _, c in ipairs(SIM.calls) do if c[1] == "QuestLogPushQuest" then n = n + 1 end end
  return n .. " push(es) " .. table.concat(o, ",")
end
SIM.calls = {}; SIM.Fire("QUEST_ACCEPTED", 102); SIM.Advance(2)
L("solo, picked up Hogger: " .. pushes())
SIM.inGroup, SIM.partyNames = true, { "Bob" }
SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.Advance(3)
SIM.calls = {}; SIM.Advance(3)
L("Bob joins (no sync yet): " .. pushes())
SIM.calls = {}; SIM.Fire("QUEST_ACCEPTED", 102); SIM.Advance(2)
L("picked up Hogger, Bob not synced: " .. pushes())
local function fromBob(m) SIM.Fire("CHAT_MSG_ADDON", "TWZQ", m, "PARTY", "Bob-Realm") end
fromBob("B|1|20"); fromBob("Q|100|0|m3/8"); fromBob("E"); SIM.Advance(3)
SIM.calls = {}; SIM.Advance(3)
L("Bob synced (nothing shared on join): " .. pushes())
SIM.calls = {}; SIM.Fire("QUEST_ACCEPTED", 101); SIM.Advance(2)
L("picked up The Defias (Bob lacks it): " .. pushes())
SIM.calls = {}; SIM.Fire("QUEST_ACCEPTED", 1, 100); SIM.Advance(2)
L("picked up Kobolds (Bob has it, old-style event args): " .. pushes())
SlashCmdList.QUESTROUTE("party pickup")
SIM.calls = {}; SIM.Fire("QUEST_ACCEPTED", 102); SIM.Advance(2)
L("after /tq party pickup (off): " .. pushes())
