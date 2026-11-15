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


local function c(t) return ((t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local f = TwizQuestFrame
f:Show(); ns.Replan(); SIM.Advance(12)
L("HEADER: " .. c(f.summary:GetText()))
if f.flags.__shown then L("FLAGS : " .. c(f.flags:GetText())) end
L("CARD  : [" .. c(f.card.glyph:GetText()) .. "] " .. c(f.card.title:GetText()) .. "  |  " .. c(f.card.sub:GetText()) .. "  [Target " .. tostring(TwizQuestTargetButton and TwizQuestTargetButton.name) .. "]")
L("LABEL : " .. c(f.upLabel:GetText()))
for i = 1, 8 do local r = select(i, nil) end
for i, r in ipairs({}) do end
local rowsShown = 0
for i = 1, 40 do
  -- rows are frames hanging off listTop; read them through the planner route instead
end
local plan = ns._plan()
for i = 2, math.min(6, #plan.route) do
  local s = plan.route[i]
  local row = ns._upNextRows and ns._upNextRows[i - 1]
  L(("ROW %d : %s%s"):format(i - 1, s.q.name .. " (" .. tostring(s.kind or s.role) .. ")", row and row.faded and "  [faded]" or ""))
end
L("MORE  : " .. c(f.more:GetText()) .. " shown=" .. tostring(f.more.__shown))
for i, r in ipairs(f.xpRows) do if r.__shown then L(("XP %d  : %s  %s"):format(i, c(r.name:GetText()), c(r.right:GetText()))) end end
L("FOOTER: toggle shown=" .. tostring(f.groupToggle.__shown) .. "  status: " .. c(f.partyLine.text:GetText()) .. "  share: " .. tostring(f.share.__shown and f.share:GetText()))
L("HEIGHT: " .. f:GetHeight())
-- a 4th quest in the list: it and everything after it fade
local plan2 = ns._plan()
if plan2.route[4] then
  plan2.route[4] = setmetatable({ q = { id = 99999, name = "A Fourth Quest" } }, { __index = plan2.route[4] })
  ns.RefreshParty()
  SIM.Advance(0.5)
  local o = {}
  for i = 1, 5 do local r = ns._upNextRows[i] if r and r.__shown then o[#o + 1] = i .. (r.faded and "=faded" or "=bright") end end
  L("FADE  : " .. table.concat(o, " "))
end
