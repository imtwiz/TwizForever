-- TwizCraft 1.14: a friend's crafting profession with no recipes -> ask their TwizCraft to read it
SIM.sent, SIM.inGroup, SIM.partyNames = {}, false, {}
C_ChatInfo = C_ChatInfo or {}
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ChatInfo.SendAddonMessage = function(p, m) if p == "TWZC" then SIM.sent[#SIM.sent + 1] = m end end
IsInGroup = function() return SIM.inGroup end
UnitInParty = function() return false end
local realUN = UnitName
UnitName = function(u) local i = u and tonumber(u:match("^party(%d)$") or "") if i then return SIM.partyNames[i] end if u == "player" then return "Kitty" end return realUN(u) end
GetSpellInfo = function(id) return "Spell " .. id end
local f = io.open(REPO .. "/tools/wowsim/planmake.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("local plan, why") - 1)
assert(loadstring(src))()
local NS = TwizCraft
local L = function(s) SIM.log[#SIM.log + 1] = s end
SIM.inGroup, SIM.partyNames = true, { "Bob", "Old" }
SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.Advance(2)
SIM.sent = {}
-- Bob (TwizCraft 1.14, version 3): Tailoring sent with no recipes; Old (older TwizCraft): Alchemy empty
for _, m in ipairs({ "B|3", "P|197|80|150|Tailoring", "P|182|95|150|Herbalism", "E" }) do SIM.Fire("CHAT_MSG_ADDON", "TWZC", m, "PARTY", "Bob-Realm") end
for _, m in ipairs({ "B|2", "P|171|40|75|Alchemy", "E" }) do SIM.Fire("CHAT_MSG_ADDON", "TWZC", m, "PARTY", "Old-Realm") end
SIM.Advance(2)
local asks = {} for _, m in ipairs(SIM.sent) do if m:sub(1, 2) == "W|" then asks[#asks + 1] = m end end
L("asked to read: " .. table.concat(asks, ", "))
NS.TogglePartyCrafters(); SIM.Advance(0.2)
local o = {}
for _, r in ipairs(NS._partyRows()) do o[#o + 1] = (r.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", "")) end
L("party: " .. table.concat(o, " / "))
-- the other side: Bob asks us to read profession 171
local asked
NS.ReadAllProfessions = function(force, line) asked = tostring(force) .. "," .. tostring(line) end
SIM.Fire("CHAT_MSG_ADDON", "TWZC", "W|171|Kitty", "PARTY", "Bob-Realm")
L("a friend asked us: ReadAllProfessions(" .. tostring(asked) .. ")")
asked = nil
SIM.Fire("CHAT_MSG_ADDON", "TWZC", "W|171|Someone", "PARTY", "Bob-Realm")
L("a request for someone else: " .. tostring(asked))
