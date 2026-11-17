-- TwizQuest: a kill message while the target's name is hidden must not error
local f = io.open(REPO .. "/tools/wowsim/quest.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("%-%- 1%) fresh plan") - 1)
assert(loadstring(src))()
issecretvalue = function(v) return v == "SECRET" end
UnitExists = function(u) return true end
UnitIsDead = function() return true end
UnitName = function(u) if u == "target" then return "SECRET" end return "Kitty" end
UnitLevel = function(u) if u == "target" then return "SECRET" end return 24 end
local fmt = (COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience."):gsub("%%s", "Razormaw Needling"):gsub("%%d", "212")
SIM.Fire("CHAT_MSG_COMBAT_XP_GAIN", fmt)
SIM.Fire("CHAT_MSG_COMBAT_XP_GAIN", "SECRET")
SIM.log[#SIM.log + 1] = "kills counted: " .. tostring(TwizQuest.db.learn.kills)
