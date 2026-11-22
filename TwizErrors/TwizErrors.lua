-- TwizErrors: quiets the game's error voice ("Not enough mana", "I can't do that yet", ...).
--   /terr          on / off (off puts your old voice setting back)
--   /terr text     also hide the matching red error text (off by default)
--   /terr status   what's on
local ADDON = ...
local DB_DEFAULTS = { enabled = true, hideText = false }
local db

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff8fe08fTwizErrors|r: " .. tostring(msg)) end
local function safe(v) if issecretvalue and issecretvalue(v) then return nil end return v end

local CVAR = "Sound_EnableErrorSpeech"
local function GetVoice() local ok, v = pcall(GetCVar, CVAR); return ok and v or nil end
local function SetVoice(v) pcall(SetCVar, CVAR, v) end

-- the spoken errors this is about: your own resources, cooldowns, busy, range/facing
local NAMES = {
    "ERR_OUT_OF_MANA", "ERR_OUT_OF_ENERGY", "ERR_OUT_OF_RAGE", "ERR_OUT_OF_FOCUS", "ERR_OUT_OF_RUNIC_POWER",
    "ERR_OUT_OF_HEALTH", "ERR_ABILITY_COOLDOWN", "ERR_SPELL_COOLDOWN", "ERR_ITEM_COOLDOWN",
    "SPELL_FAILED_NOT_READY", "SPELL_FAILED_SPELL_IN_PROGRESS", "SPELL_FAILED_NO_POWER",
    "ERR_GENERIC_NO_TARGET", "SPELL_FAILED_BAD_TARGETS", "ERR_NO_ATTACK_TARGET", "ERR_BADATTACKFACING",
    "ERR_BADATTACKPOS", "SPELL_FAILED_UNIT_NOT_INFRONT", "ERR_SPELL_OUT_OF_RANGE", "SPELL_FAILED_OUT_OF_RANGE",
    "SPELL_FAILED_MOVING", "ERR_INVALID_ATTACK_TARGET",
}
local PATTERNS = { "not enough", "not ready", "can't do that yet", "another action is in progress",
    "out of range", "must be facing", "no target", "invalid target", "can't do that while moving" }
local spam = {}
local function Build()
    for _, k in ipairs(NAMES) do local v = _G[k]; if type(v) == "string" then spam[v] = true end end
end
local function IsSpam(msg)
    msg = safe(msg)
    if type(msg) ~= "string" then return false end
    if spam[msg] then return true end
    local low = msg:lower()
    for _, p in ipairs(PATTERNS) do if low:find(p, 1, true) then return true end end
    return false
end

-- optional: hide the red text for those errors (everything else still shows)
local hooked
local function HookText()
    if hooked or not UIErrorsFrame or not UIErrorsFrame.GetScript then return end
    local orig = UIErrorsFrame:GetScript("OnEvent")
    if not orig then return end
    hooked = true
    UIErrorsFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "UI_ERROR_MESSAGE" and db and db.enabled and db.hideText then
            local _, msg = ...
            if IsSpam(msg) then return end
        end
        return orig(self, event, ...)
    end)
end

local function Apply()
    if not db then return end
    if db.enabled then
        local cur = GetVoice()
        if cur and cur ~= "0" and db.orig == nil then db.orig = cur end
        SetVoice("0")
        if db.hideText then HookText() end
    else
        if db.orig ~= nil then SetVoice(db.orig); db.orig = nil
        elseif GetVoice() == "0" then SetVoice("1") end
    end
end

local function Status()
    Print(("error voice: %s (game setting %s = %s); red error text for those errors: %s")
        :format(db.enabled and "|cff8fe08fsilenced|r" or "normal", CVAR, tostring(GetVoice()),
        (db.enabled and db.hideText) and "hidden" or "shown"))
end

SLASH_TWIZERRORS1 = "/terr"
SLASH_TWIZERRORS2 = "/twizerrors"
SlashCmdList["TWIZERRORS"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "text" then
        db.hideText = not db.hideText
        if db.hideText then db.enabled = true end
        Apply(); Status()
    elseif cmd == "status" then Status()
    elseif cmd == "help" or cmd == "?" then
        Print("/terr - silence the error voice on/off   /terr text - also hide the red text for those errors   /terr status")
    elseif cmd == "on" then db.enabled = true; Apply(); Status()
    elseif cmd == "off" then db.enabled = false; Apply(); Status()
    else db.enabled = not db.enabled; Apply(); Status() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        TwizErrorsDB = TwizErrorsDB or {}
        db = TwizErrorsDB
        for k, v in pairs(DB_DEFAULTS) do if db[k] == nil then db[k] = v end end
        Build()
    elseif event == "PLAYER_ENTERING_WORLD" then
        Apply() -- again on every load screen, in case something turned the voice back on
    end
end)

TwizErrors = { IsSpam = IsSpam, Apply = Apply }
