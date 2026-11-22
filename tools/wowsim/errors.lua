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
