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

C_QuestLog.GetQuestTagInfo = function(id) if id == 101 then return { tagID = 81, tagName = "Dungeon" } end end
-- 100 is a class quest (Questie requiredClasses), 103 a normal one
local realQ = ns.Q
ns.Q = function(id, f) if f == "requiredClasses" and id == 100 then return 8 end return realQ(id, f) end
table.insert(SIM.quests, { title = "Old Gray Errand", questID = 103, isHeader = false, objectives = {} })
local shown
StaticPopup_Show = function(w, a1, a2) shown = { w, a1, a2 } return shown end
local function abandoned()
  local o, sel = {}, nil
  for _, c in ipairs(SIM.calls) do
    if c[1] == "SetSelectedQuest" then sel = c[2] elseif c[1] == "AbandonQuest" then o[#o + 1] = sel end
  end
  return table.concat(o, ",")
end
local function clean(t) return ((t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n", " ")) end
-- plain Drop All keeps the dungeon quest (101)
SIM.calls = {}
TwizQuestFrame.dropAll:Click()
L("Drop All asks: " .. tostring(shown[2]) .. " quests" .. clean(shown[3]))
StaticPopupDialogs.TWIZQUEST_ABANDON_ALL.OnAccept(nil, shown.data); SIM.Advance(1)
L("abandoned: " .. abandoned())
-- shift-click drops dungeon quests too
IsShiftKeyDown = function() return true end
SIM.calls = {}
TwizQuestFrame.dropAll:Click()
IsShiftKeyDown = function() return false end
L("shift-click asks: " .. tostring(shown[2]) .. " quests" .. clean(shown[3]))
StaticPopupDialogs.TWIZQUEST_ABANDON_ALL.OnAccept(nil, shown.data); SIM.Advance(1)
L("abandoned: " .. abandoned())
