-- TwizQuest learning: watches how you actually play and tunes the estimates.
--   * how many combat seconds each kill takes
--   * how long you rest (eat/drink) per kill
--   * your running and mounted speed
--   * how kill and quest XP on this server compares with the formulas
local ADDON, NS = ...

local f = CreateFrame("Frame")
local ALPHA = 0.15

local function Ema(old, new, alpha)
    return old + (alpha or ALPHA) * (new - old)
end

-- "%s dies, you gain %d experience." -> pattern capturing name and number
local function ToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    fmt = fmt:gsub("%%%d?%$?s", "(.+)")
    fmt = fmt:gsub("%%%d?%$?d", "(%%d+)")
    return "^" .. fmt
end
local KILL_FMT = COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience."
local KILL_PATTERN = ToPattern(KILL_FMT)
local PLAIN_PATTERN = KILL_PATTERN and (KILL_PATTERN .. "$")

-- combat bookkeeping
local combatStart, fightKills = nil, 0
local restStart, restKills = nil, 0
local lastX, lastY, lastInst, lastT

local function OnKill(name, total, plain)
    local L = NS.db.learn
    fightKills = fightKills + 1
    L.kills = L.kills + 1
    local lvl = UnitLevel("player")
    local mob
    if UnitExists("target") and UnitIsDead("target") and UnitName("target") == name then
        mob = UnitLevel("target")
    end
    if plain and mob and mob > 0 then
        local expected = NS.FormulaKillXP(lvl, mob)
        if UnitClassification and UnitClassification("target"):find("elite") then expected = expected * 2 end
        if expected > 0 then
            local r = total / expected
            if r > 0.3 and r < 4 then L.killXPRatio = Ema(L.killXPRatio, r, 0.1) end
        end
    end
end

local function Sample()
    if not NS.Bridge() then return end
    local x, y, inst = NS.PlayerPos()
    local t = GetTime()
    local L = NS.db.learn
    if x and lastX and inst == lastInst and t > lastT then
        local d = NS.Dist(x, y, lastX, lastY)
        local v = d / (t - lastT)
        local moving = v > 1.5
        if moving and not (UnitOnTaxi and UnitOnTaxi("player")) and not UnitAffectingCombat("player")
            and v < 60 and not (IsSwimming and IsSwimming()) then
            if IsMounted and IsMounted() then
                L.mountSeen = L.mountSeen + 1
                L.mountSpeed = (L.mountSpeed > 0) and Ema(L.mountSpeed, v) or v
            elseif v > 3 then
                L.runSpeed = Ema(L.runSpeed, v, 0.05)
            end
            L.samples = L.samples + 1
        end
        -- rest ends when you start moving or pull again
        if restStart and moving then
            local rest = t - restStart
            if restKills > 0 and rest < 120 then
                L.restPerKill = Ema(L.restPerKill, rest / restKills)
            end
            restStart = nil
        end
    end
    lastX, lastY, lastInst, lastT = x, y, inst, t
end

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
pcall(f.RegisterEvent, f, "QUEST_TURNED_IN")

f:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        QuestRouteDB = QuestRouteDB or {}
        local db = QuestRouteDB
        for k, v in pairs(NS.DEFAULTS) do
            if db[k] == nil then
                if type(v) == "table" then
                    db[k] = {}
                    for k2, v2 in pairs(v) do db[k][k2] = v2 end
                else db[k] = v end
            end
        end
        for k, v in pairs(NS.DEFAULTS.learn) do if db.learn[k] == nil then db.learn[k] = v end end
        NS.db = db
        C_Timer.NewTicker(0.5, Sample)
        return
    end
    if not NS.db then return end
    local L = NS.db.learn

    if event == "PLAYER_REGEN_DISABLED" then
        combatStart, fightKills = GetTime(), 0
        if restStart then restStart = nil end   -- pulled before moving: rest ended
    elseif event == "PLAYER_REGEN_ENABLED" then
        if combatStart and fightKills > 0 then
            local per = (GetTime() - combatStart) / fightKills
            if per > 2 and per < 180 then L.secPerKill = Ema(L.secPerKill, per) end
            restStart, restKills = GetTime(), fightKills
        end
        combatStart = nil
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        local msg = a1 or ""
        local name, xp = msg:match(KILL_PATTERN or "^$")
        if name and tonumber(xp) then
            -- only a plain message (no rested/group bonus text) is clean enough to learn XP from
            local plain = PLAIN_PATTERN and msg:match(PLAIN_PATTERN) ~= nil
            OnKill(name, tonumber(xp), plain)
        end
    elseif event == "QUEST_TURNED_IN" then
        local id, xp = a1, a2
        if NS.Bridge() and id and type(xp) == "number" and xp > 0 then
            local raw = NS.QuestXP(id) / L.questXPRatio
            if raw > 0 then
                local r = xp / raw
                if r > 0.3 and r < 4 then L.questXPRatio = Ema(L.questXPRatio, r, 0.2) end
            end
            L.quests = L.quests + 1
        end
    end
end)
