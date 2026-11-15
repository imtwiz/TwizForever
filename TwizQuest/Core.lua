-- TwizQuest core: settings, the bridge into Questie's database, and geometry.
local ADDON, NS = ...
TwizQuest = NS
BINDING_HEADER_TWIZQUEST = "TwizQuest"
BINDING_NAME_TWIZQUEST_NEXT = "Waypoint to step 1"
_G["BINDING_NAME_CLICK TwizQuestTargetButton:LeftButton"] = "Target step 1's mob or NPC"

NS.DEFAULTS = {
    horizon   = 60,    -- minutes of play to plan
    maxAbove  = 3,     -- skip quests more than this many levels above you
    maxDist   = 3000,  -- yards; ignore quest givers farther than this
    elites    = false, -- plan quests that need elite kills
    autoWay   = true,  -- put a waypoint on step 1 automatically
    service   = true,  -- add a sell & repair stop when bags are nearly full or gear is breaking
    sellAt    = 2,     -- free bag slots that trigger the sell stop
    repairAt  = 0.25,  -- lowest durability that triggers the repair stop
    auto      = true,  -- keep the plan updated by itself
    party     = true,  -- sync quests with party members who run TwizQuest
    partyShare = true, -- share quests a party member doesn't have when they join
    partyHelp = true,  -- stay to help party members finish kills on shared quests
    shown     = true,
    learn = {
        runSpeed    = 7.0,  -- yards/sec on foot
        mountSpeed  = 0,    -- 0 = not seen you mounted yet
        mountSeen   = 0,
        secPerKill  = 18,   -- combat seconds per kill
        restPerKill = 8,    -- eating/drinking seconds per kill
        killXPRatio = 1.0,  -- actual / formula kill XP
        questXPRatio = 1.0, -- actual / database quest XP
        detour      = 1.35, -- real path length vs straight line
        kills = 0, quests = 0, samples = 0,
    },
}

function NS.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ddffTwizQuest:|r " .. msg)
end

function NS.safe(v)
    if v == nil then return nil end
    if issecretvalue then
        local ok, s = pcall(issecretvalue, v)
        if ok and s then return nil end
    end
    return v
end

------------------------------------------------------------------------
-- Questie bridge
------------------------------------------------------------------------
local bridge
function NS.Bridge()
    if bridge then return bridge end
    if not (QuestieLoader and Questie and Questie.started) then return nil, "Questie is still loading" end
    local ok, DB = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
    local ok2, ZoneDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
    local ok3, QuestXP = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestXP")
    local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
    if not (ok and DB and DB.QueryQuestSingle) then return nil, "Questie's database isn't available" end
    if not (ok2 and ZoneDB and ZoneDB.GetUiMapIdByAreaId) then return nil, "Questie's zone data isn't available" end
    if not HBD then return nil, "HereBeDragons (comes with Questie/TomTom) isn't loaded" end
    bridge = { DB = DB, ZoneDB = ZoneDB, QuestXP = ok3 and QuestXP or nil, HBD = HBD }
    return bridge
end

function NS.Q(id, field)
    local ok, v = pcall(bridge.DB.QueryQuestSingle, id, field)
    return ok and v or nil
end
function NS.N(id, field)
    local ok, v = pcall(bridge.DB.QueryNPCSingle, id, field)
    return ok and v or nil
end
function NS.O(id, field)
    local ok, v = pcall(bridge.DB.QueryObjectSingle, id, field)
    return ok and v or nil
end
function NS.I(id, field)
    local ok, v = pcall(bridge.DB.QueryItemSingle, id, field)
    return ok and v or nil
end

------------------------------------------------------------------------
-- Geometry: Questie stores spawns as {[areaId] = {{x, y}, ...}} in 0-100
-- map percentages. HereBeDragons turns those into world yards.
------------------------------------------------------------------------
local uiMapCache = {}
local function UiMap(areaId)
    local v = uiMapCache[areaId]
    if v == nil then
        local ok, m = pcall(bridge.ZoneDB.GetUiMapIdByAreaId, bridge.ZoneDB, areaId)
        v = (ok and m) or false
        uiMapCache[areaId] = v
    end
    return v or nil
end

-- Returns world x, y, instance, uiMapId
function NS.World(areaId, x, y)
    local map = UiMap(areaId)
    if not map or not x or not y then return nil end
    local wx, wy, inst = bridge.HBD:GetWorldCoordinatesFromZone(x / 100, y / 100, map)
    if not wx then return nil end
    return wx, wy, inst, map
end

function NS.PlayerPos()
    return bridge.HBD:GetPlayerWorldPosition()
end

function NS.Dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-- Seconds to travel a straight-line distance, using what we've learned.
function NS.TravelTime(d)
    local L = NS.db.learn
    if d < 1 then return 0 end
    local path = d * L.detour
    if L.mountSpeed > 0 and L.mountSeen >= 10 and path > 150 then
        return 3 + path / L.mountSpeed      -- 3s to mount up
    end
    return path / L.runSpeed
end

------------------------------------------------------------------------
-- Classic kill XP formula, scaled by what you actually get.
------------------------------------------------------------------------
local function ZeroDiff(lvl)
    if lvl < 8 then return 5 elseif lvl < 10 then return 6 elseif lvl < 12 then return 7
    elseif lvl < 16 then return 8 elseif lvl < 20 then return 9 elseif lvl < 30 then return 11
    elseif lvl < 40 then return 12 elseif lvl < 45 then return 13 elseif lvl < 50 then return 14
    elseif lvl < 55 then return 15 elseif lvl < 60 then return 16 else return 17 end
end

local function GrayLevel(lvl)
    if lvl <= 5 then return 0 elseif lvl <= 39 then return lvl - 5 - math.floor(lvl / 10)
    elseif lvl <= 59 then return lvl - 1 - math.floor(lvl / 5) else return lvl - 9 end
end
NS.GrayLevel = GrayLevel

function NS.FormulaKillXP(player, mob)
    if mob <= GrayLevel(player) then return 0 end
    local base = player * 5 + 45
    if mob >= player then
        return base * (1 + 0.05 * math.min(mob - player, 4))
    end
    return base * (1 - (player - mob) / ZeroDiff(player))
end

function NS.KillXP(player, mob, elite)
    local xp = NS.FormulaKillXP(player, mob) * NS.db.learn.killXPRatio
    if elite then xp = xp * 2 end
    return xp
end

function NS.QuestXP(id)
    local qx = bridge.QuestXP
    if not qx or not qx.GetQuestLogRewardXP then return 0 end
    local ok, xp = pcall(qx.GetQuestLogRewardXP, qx, id)
    return (ok and tonumber(xp) or 0) * NS.db.learn.questXPRatio
end

function NS.FormatTime(sec)
    sec = math.floor(sec + 0.5)
    if sec < 60 then return sec .. "s" end
    if sec < 3600 then return math.floor(sec / 60) .. "m" end
    return ("%dh %dm"):format(sec / 3600, (sec % 3600) / 60)
end

function NS.FormatNum(n)
    n = math.floor(n + 0.5)
    local s = tostring(n)
    while true do
        local k
        s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return s
end
