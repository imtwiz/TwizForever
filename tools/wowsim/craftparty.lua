-- TwizCraft party crafters: share professions/recipes, browse, tooltip makers
SIM.sent, SIM.inGroup, SIM.partyNames = {}, false, {}
C_ChatInfo = C_ChatInfo or {}
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ChatInfo.SendAddonMessage = function(p, m) if p == "TWZC" then SIM.sent[#SIM.sent + 1] = m end end
IsInGroup = function() return SIM.inGroup end
UnitInParty = function(n) for _, v in ipairs(SIM.partyNames) do if v == n then return true end end return false end
local realUN = UnitName
UnitName = function(u) local i = u and tonumber(u:match("^party(%d)$") or "") if i then return SIM.partyNames[i] end return realUN(u) end
Ambiguate = function(n) return (n:gsub("%-.*", "")) end
GetSpellInfo = function(id) return "Spell " .. id end
local f = io.open(REPO .. "/tools/wowsim/planmake.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("local plan, why") - 1)
assert(loadstring(src))()
local NS = TwizCraft
for _, r in pairs(NS.Char().profs[202].recipes) do r.learned = true end
NS.Professions = function() return { { name = "Engineering", skill = 82, max = 150, line = 202 } } end
local L = function(s) SIM.log[#SIM.log + 1] = s end
-- Bob joins: we announce ourselves and send our professions
SIM.inGroup, SIM.partyNames = true, { "Bob" }
SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.Advance(3)
L("I sent: " .. table.concat(SIM.sent, "  ||  "))
-- replay exactly what we sent as if Bob sent it (round trip), as Bob's Engineering
local mine = SIM.sent
for _, m in ipairs(mine) do if not m:match("^H") then SIM.Fire("CHAT_MSG_ADDON", "TWZC", m, "PARTY", "Bob-Realm") end end
SIM.Advance(1)
L("party crafters: " .. NS.PartyCrafterCount())
L("who can make Coarse Dynamite (4365): " .. table.concat(NS.PartyMakers(4365), ", "))
L("who can make Linen (2589): " .. (#NS.PartyMakers(2589) > 0 and table.concat(NS.PartyMakers(2589), ", ") or "nobody"))
-- window
NS.TogglePartyCrafters(); SIM.Advance(0.2)
local function rowtext()
  local o = {}
  for _, r in ipairs(NS._partyRows()) do o[#o + 1] = (r.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  return table.concat(o, " / ")
end
L("window rows: " .. rowtext())
NS._partyOpen["Bob:202"] = true
L("expanded: " .. rowtext())
-- main window button

-- Bob leaves
SIM.inGroup, SIM.partyNames = false, {}
SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.Advance(1)
L("after Bob left: crafters " .. NS.PartyCrafterCount())
