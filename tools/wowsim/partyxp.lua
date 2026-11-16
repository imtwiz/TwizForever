-- TwizQuest: XP bars for every party member (synced, waiting for XP, or without TwizQuest)
SIM.sent, SIM.inGroup, SIM.partyNames = {}, false, {}
C_ChatInfo = C_ChatInfo or {}
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ChatInfo.SendAddonMessage = function(prefix, msg, chan) SIM.sent[#SIM.sent + 1] = msg end
IsInGroup = function() return SIM.inGroup end
IsInRaid = function() return false end
UnitInParty = function() return false end
local realUnitName = UnitName
UnitName = function(u) local i = u and tonumber(u:match("^party(%d)$") or "") if i then return SIM.partyNames[i] end return realUnitName(u) end
local realLevel = UnitLevel
UnitLevel = function(u) if u and u:match("^party") then return 18 end return realLevel(u) end
local f = io.open(REPO .. "/tools/wowsim/quest.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("%-%- 1%) fresh plan") - 1)
assert(loadstring(src))()
local ns = TwizQuest
local L = function(s) SIM.log[#SIM.log + 1] = s end
TwizQuestFrame:Show()
SIM.inGroup, SIM.partyNames = true, { "Bob", "Carl" }
SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.Advance(3)
local function fromBob(m) SIM.Fire("CHAT_MSG_ADDON", "TWZQ", m, "PARTY", "Bob-Realm") end
fromBob("B|1|20"); fromBob("E"); SIM.Advance(3)
local function c(t) return ((t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function bars() local o = {} for _, r in ipairs(TwizQuestFrame.xpRows) do if r.__shown then o[#o + 1] = c(r.name:GetText()) .. ": " .. c(r.right:GetText()) end end return table.concat(o, " | ") end
L("before Bob's XP: " .. bars())
fromBob("X|20|5000|13900|0|9000"); SIM.Advance(2)
L("after: " .. bars())
local xpSent = 0 for _, m in ipairs(SIM.sent) do if m:match("^X|") then xpSent = xpSent + 1 end end
SIM.sent = {}; SIM.Advance(31)
local again = 0 for _, m in ipairs(SIM.sent) do if m:match("^X|") then again = again + 1 end end
L(("our XP sent %d, resent in 30s: %d"):format(xpSent, again))
