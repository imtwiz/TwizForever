-- Party sync with Forever names: characters have surnames, so addon messages
-- arrive from "First Last" (or "First-Last", with or without "-Realm") while
-- UnitName() gives only "First". Checks fail the run (they add to SIM.errors).
SIM.sent, SIM.inGroup = {}, false
SIM.partyFull = {}   -- party1..4 full names, e.g. "Bob Stone"
C_ChatInfo = C_ChatInfo or {}
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ChatInfo.SendAddonMessage = function(prefix, msg) SIM.sent[#SIM.sent + 1] = msg end
IsInGroup = function() return SIM.inGroup end
IsInRaid = function() return false end
Ambiguate = function(n) return (n:gsub("%-.*", "")) end
QuestLogPushQuest = function() end
local function Full(u)
  if u == "player" then return "Twiz Forever" end
  local i = u and tonumber(u:match("^party(%d)$") or "")
  return i and SIM.partyFull[i] or nil
end
local realUnitName = UnitName
UnitName = function(u)
  local full = Full(u)
  if full then return (full:match("^(%S+)")) end   -- the game gives the first name only
  if u and u:match("^party") then return nil end
  return realUnitName(u)
end
GetUnitName = function(u) return Full(u) end

local f = io.open(REPO .. "/tools/wowsim/quest.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("%-%- 1%) fresh plan") - 1)
assert(loadstring(src))()
local ns = TwizQuest
C_QuestLog.IsComplete = function() return false end
C_QuestLog.IsPushableQuest = function() return true end
SIM.quests = {
  { title = "The Defias", questID = 101, isHeader = false, objectives = { { type = "monster", text = "Defias Thug slain: 2/8", numRequired = 8, numFulfilled = 2, finished = false } } },
}

local function check(ok, label)
  SIM.log[#SIM.log + 1] = (ok and "ok   " or "FAIL ") .. label
  if not ok then SIM.errors[#SIM.errors + 1] = "check failed: " .. label end
end
local function list(t) table.sort(t) return table.concat(t, ",") end
local function names(t) local o = {} for k in pairs(t) do o[#o + 1] = k end return list(o) end
local function join(party)
  SIM.inGroup, SIM.partyFull = false, {}
  SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.Advance(1)
  SIM.inGroup, SIM.partyFull = true, party
  SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.Advance(3)
end
local function log(sender, quest)
  for _, m in ipairs({ "B|1|19", "Q|" .. quest .. "|0|m3/8", "E" }) do SIM.Fire("CHAT_MSG_ADDON", "TWZQ", m, "PARTY", sender) end
  SIM.Advance(2)
end

-- every form the sender name can take
for _, sender in ipairs({ "Bob Stone", "Bob-Stone", "Bob Stone-Realm", "Bob-Stone-Realm", "Bob", "Bob-Realm", "bob stone" }) do
  join({ "Bob Stone" })
  log(sender, 100)
  local st = ns.PartyStatus()
  check(list(st.members) == "Bob" and #st.noAddon == 0 and ns.party.Bob and ns.party.Bob.quests[100] ~= nil,
    ("sender %q is party member Bob (members: %s)"):format(sender, list(st.members)))
end
local line = TwizQuestFrame.partyLine.text:GetText() or ""
check(line:find("Bob", 1, true) ~= nil, "party line names Bob: " .. line)

-- your own messages come back to you: not a party member
join({ "Bob Stone" })
log("Twiz Forever", 100); log("Twiz", 100); log("Twiz-Forever-Realm", 100)
check(names(ns.party) == "", "own messages are ignored (party: " .. names(ns.party) .. ")")

-- people who are not in the party, including a name that only starts the same
log("Eve Adams", 100); log("Bobby Tables", 100); log("Bo", 100)
check(names(ns.party) == "", "strangers are ignored (party: " .. names(ns.party) .. ")")
check(#ns.PartyStatus().noAddon == 1, "Bob is still listed as not synced")

-- two party members with the same first name stay apart
join({ "Bob Stone", "Bob Hill" })
log("Bob Hill", 100); log("Bob Stone-Realm", 102)
local st = ns.PartyStatus()
check(list(st.members) == "Bob Hill,Bob Stone", "two Bobs are two members: " .. list(st.members))
check(ns.party["Bob Hill"] and ns.party["Bob Hill"].quests[100] and not ns.party["Bob Hill"].quests[102],
  "Bob Hill has only his own quest")
check(ns.party["Bob Stone"] and ns.party["Bob Stone"].quests[102] and not ns.party["Bob Stone"].quests[100],
  "Bob Stone has only his own quest")
log("Bob", 103)
check(not ns.party["Bob Hill"].quests[103] and not ns.party["Bob Stone"].quests[103], "a bare \"Bob\" is nobody when there are two")

-- someone with your first name
join({ "Twiz Other" })
log("Twiz Other", 100)
check(list(ns.PartyStatus().members) == "Twiz", "a party member sharing your first name syncs")
log("Twiz Forever", 102)
check(not ns.party.Twiz.quests[102], "and your own messages are still ignored")

-- a member leaves: their data goes
join({ "Bob Stone" }); log("Bob Stone", 100)
SIM.inGroup, SIM.partyFull = false, {}
SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.Advance(1)
check(names(ns.party) == "", "leaving the party clears it")
