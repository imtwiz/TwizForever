-- TwizErrors: silences the error voice, restores it, optional red-text filter
local L = function(s) SIM.log[#SIM.log + 1] = s end
local cvars = { Sound_EnableErrorSpeech = "1" }
GetCVar = function(k) return cvars[k] end
SetCVar = function(k, v) cvars[k] = tostring(v) end
ERR_OUT_OF_MANA = "Not enough mana"
ERR_OUT_OF_ENERGY = "Not enough energy"
local shown = {}
UIErrorsFrame = CreateFrame("Frame", "UIErrorsFrame")
UIErrorsFrame:SetScript("OnEvent", function(_, e, t, msg) shown[#shown + 1] = msg end)
seterrorhandler = function(f) SIM.errorhandler = f end
geterrorhandler = function() return function() end end
debugstack = function() return "stack line 1\nstack line 2" end
SIM.LoadAddon(REPO .. "/TwizErrors", "TwizErrors")
SIM.Fire("ADDON_LOADED", "TwizErrors")
SIM.Fire("PLAYER_ENTERING_WORLD")
L("voice after login: " .. cvars.Sound_EnableErrorSpeech)
assert(cvars.Sound_EnableErrorSpeech == "0")
SlashCmdList.TWIZERRORS("")
L("voice after /terr (off): " .. cvars.Sound_EnableErrorSpeech)
assert(cvars.Sound_EnableErrorSpeech == "1", "restored")
SlashCmdList.TWIZERRORS("")
assert(cvars.Sound_EnableErrorSpeech == "0")
local h = UIErrorsFrame:GetScript("OnEvent")
h(UIErrorsFrame, "UI_ERROR_MESSAGE", 1, "Not enough mana")
L("text filter off, shown: " .. #shown)
assert(#shown == 1)
SlashCmdList.TWIZERRORS("text")
h = UIErrorsFrame:GetScript("OnEvent")
h(UIErrorsFrame, "UI_ERROR_MESSAGE", 1, "Not enough mana")
h(UIErrorsFrame, "UI_ERROR_MESSAGE", 1, "I can't do that yet")
h(UIErrorsFrame, "UI_ERROR_MESSAGE", 1, "Inventory is full.")
L("text filter on, shown: " .. table.concat(shown, " | "))
assert(#shown == 2 and shown[2] == "Inventory is full.")
L("saved: enabled=" .. tostring(TwizErrorsDB.enabled) .. " hideText=" .. tostring(TwizErrorsDB.hideText) .. " orig=" .. tostring(TwizErrorsDB.orig))
-- 1.1.0: the bug catcher
local handler = SIM.errorhandler
assert(type(handler) == "function", "error handler installed")
handler("Interface/AddOns/TwizHeal/TwizHeal.lua:123: attempt to index a nil value")
handler("Interface/AddOns/TwizHeal/TwizHeal.lua:123: attempt to index a nil value")
handler("Interface/AddOns/Questie/Modules/X.lua:9: boom")
L("bugs: " .. TwizErrors.BugCount() .. " total, TwizHeal " .. TwizErrors.BugCount("TwizHeal") .. ", Questie " .. TwizErrors.BugCount("Questie"))
assert(TwizErrors.BugCount() == 3 and TwizErrors.BugCount("TwizHeal") == 2)
assert(#TwizErrorsDB.bugs == 2, "same error counted, not duplicated")
SIM.Fire("ADDON_ACTION_BLOCKED", "TwizBuff", "CastSpellByName")
L("blocked entry: " .. TwizErrorsDB.bugs[1].msg .. " (" .. TwizErrorsDB.bugs[1].addon .. ")")
SlashCmdList.TWIZERRORS("bugs")
L("window: " .. tostring(TwizErrorsBugFrame and TwizErrorsBugFrame:IsShown()))
SlashCmdList.TWIZERRORS("clear")
assert(#TwizErrorsDB.bugs == 0)
L("cleared")
