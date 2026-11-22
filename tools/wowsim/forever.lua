-- TwizForever: the menu lists every Twiz addon, reads settings, runs their slash commands
local L = function(s) SIM.log[#SIM.log + 1] = s end
local installed = { "TwizAH", "TwizQuest", "TwizCraft", "TwizChef", "TwizBuff", "TwizHeal", "TwizErrors", "TwizForever" }
local loaded = { TwizHeal = true, TwizErrors = true, TwizForever = true, TwizBuff = true }
local enabled = { TwizHeal = true, TwizErrors = true, TwizForever = true, TwizBuff = true, TwizAH = false }
C_AddOns = {
  GetNumAddOns = function() return #installed end,
  GetAddOnInfo = function(i) return installed[i] end,
  IsAddOnLoaded = function(n) return loaded[n] or false end,
  GetAddOnMetadata = function(n, k) return k == "Version" and "9.9.9" or nil end,
  GetAddOnEnableState = function(n, who) return enabled[n] and 2 or 0 end,
  EnableAddOn = function(n) enabled[n] = true end,
  DisableAddOn = function(n) enabled[n] = false end,
}
UnitName = function() return "Kitty" end
local ran = {}
SlashCmdList = SlashCmdList or {}
SlashCmdList.TWIZHEAL = function(a) ran[#ran + 1] = "th " .. a; if a == "guard" then TwizHealDB.combatGuard = TwizHealDB.combatGuard == false end end
SlashCmdList.TWIZERRORS = function(a) ran[#ran + 1] = "terr " .. a end
SlashCmdList.TWIZBUFF = function(a) ran[#ran + 1] = "tb " .. a end
TwizHealDB = { shown = true, castInfo = true, combatGuard = true, feedback = true }
TwizErrorsDB = { enabled = true, hideText = false }
TwizBuffDB = { wheel = true, thorns = true, strangers = true }
C_Timer = C_Timer or {}; C_Timer.After = function(_, f) f() end

SIM.LoadAddon(REPO .. "/TwizForever", "TwizForever")
SIM.Fire("ADDON_LOADED", "TwizForever"); SIM.Fire("PLAYER_LOGIN")
SlashCmdList.TWIZFOREVER("")
local NS = TwizForever
assert(TwizForeverFrame and TwizForeverFrame:IsShown(), "menu opens")
L("addons listed: " .. #NS.ADDONS)
-- pick TwizHeal (6), uncheck the 90% blocker
for i, a in ipairs(NS.ADDONS) do if a.name == "TwizHeal" then NS.Refresh(); TwizForever_Toggle(); TwizForever_Toggle() end end
local idx; for i, a in ipairs(NS.ADDONS) do if a.name == "TwizHeal" then idx = i end end
TwizForeverDB.selected = idx
-- simulate clicking the row
NS.Run(NS.ADDONS[idx], NS.ADDONS[idx].settings[4][3](false))
L("ran: " .. table.concat(ran, ", ") .. "; combatGuard now " .. tostring(TwizHealDB.combatGuard))
assert(ran[1] == "th guard" and TwizHealDB.combatGuard == false)
-- every addon's settings read without errors from a plausible DB
for _, a in ipairs(NS.ADDONS) do
  for _, s in ipairs(a.settings) do
    local ok, err = pcall(s[2], {})
    assert(ok, a.name .. " " .. s[1] .. ": " .. tostring(err))
    assert(type(s[3](true)) == "string" and type(s[3](false)) == "string")
  end
end
L(("states: TwizHeal on=%s, TwizAH installed=%s enabled=%s, TwizOpen installed=%s"):format(
  tostring(NS.Enabled("TwizHeal")), tostring(NS.Exists("TwizAH")), tostring(NS.Enabled("TwizAH")), tostring(NS.Exists("TwizOpen"))))
SlashCmdList.TWIZFOREVER("minimap")
L("minimap: " .. tostring(TwizForeverDB.minimap))
SlashCmdList.TWIZFOREVER("minimap")
for i = 1, #NS.ADDONS do NS.Select(i) end
L("selected every addon's page without errors")
NS.Select(idx)
