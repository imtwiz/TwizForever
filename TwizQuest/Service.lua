-- TwizQuest service stops: when your bags are nearly full or your gear is close
-- to breaking, the route gets a "Sell & repair" stop at the nearest friendly
-- vendor (a repairer when gear needs it), placed where it costs the least time.
local ADDON, NS = ...

local services -- [instance] = { { x, y, map, mx, my, repair = bool, who } }
local trainers -- [instance] = your class trainers { x, y, map, mx, my, who } (1.21.0)

-- Built once from Questie's NPC data (may pause between frames like the bankers).
function NS.PrepareServices()
    if services then return end
    services, trainers = {}, {}
    local B = NS.Bridge()
    local flags = B and B.DB.npcFlags
    local VENDOR = flags and flags.VENDOR or 128
    local REPAIR = flags and flags.REPAIR or 4096
    local TRAINER = flags and (flags.CLASS_TRAINER or flags.TRAINER) or 16
    local className = (UnitClass("player") or ""):lower()
    if not (B and B.DB.NPCPointers and bit and bit.band) then return end
    local faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
    local n = 0
    for npc in pairs(B.DB.NPCPointers) do
        n = n + 1
        if n % 300 == 0 and NS.Yield then NS.Yield() end
        local f = NS.N(npc, "npcFlags")
        -- your class trainer ("Druid Trainer"), friendly to you
        if f and className ~= "" and bit.band(f, TRAINER) ~= 0 then
            local sub = NS.N(npc, "subName")
            local fr = NS.N(npc, "friendlyToFaction")
            if type(sub) == "string" and sub:lower():find(className, 1, true) and sub:lower():find("trainer", 1, true)
                and fr and fr:find(faction, 1, true) then
                local who = NS.N(npc, "name")
                local spawns = NS.N(npc, "spawns")
                for areaId, list in pairs(type(spawns) == "table" and spawns or {}) do
                    for _, c in ipairs(type(list) == "table" and list or {}) do
                        if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and c[1] > 0 then
                            local wx, wy, i, map = NS.World(areaId, c[1], c[2])
                            if wx then
                                trainers[i] = trainers[i] or {}
                                table.insert(trainers[i], { x = wx, y = wy, map = map, mx = c[1], my = c[2], who = who })
                            end
                        end
                    end
                end
            end
        end
        if f and bit.band(f, VENDOR) ~= 0 then
            local fr = NS.N(npc, "friendlyToFaction")
            if fr and fr:find(faction, 1, true) then
                local repair = bit.band(f, REPAIR) ~= 0
                local who = NS.N(npc, "name")
                local spawns = NS.N(npc, "spawns")
                for areaId, list in pairs(type(spawns) == "table" and spawns or {}) do
                    for _, c in ipairs(type(list) == "table" and list or {}) do
                        if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and c[1] > 0 then
                            local wx, wy, i, map = NS.World(areaId, c[1], c[2])
                            if wx then
                                services[i] = services[i] or {}
                                table.insert(services[i], { x = wx, y = wy, map = map, mx = c[1], my = c[2],
                                    repair = repair, who = who })
                            end
                        end
                    end
                end
            end
        end
    end
end

local function FreeSlots()
    local free = 0
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        local ok, n = pcall(C_Container.GetContainerNumFreeSlots, bag)
        if ok and n then free = free + n end
    end
    return free
end

local function LowestDurability()
    local low = 1
    if not GetInventoryItemDurability then return low end
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then low = math.min(low, cur / max) end
    end
    return low
end

-- returns needRepair, reason text  (nil if nothing needed)
function NS.ServiceNeed()
    if not NS.db.service then return nil end
    -- just visited a vendor, or you dismissed the stop: leave it alone for a while
    if NS.serviceSnooze and GetTime() < NS.serviceSnooze then return nil end
    local free = FreeSlots()
    local dur = LowestDurability()
    local needRepair = dur <= (NS.db.repairAt or 0.25)
    local needSell = free <= (NS.db.sellAt or 2)
    if not (needRepair or needSell) then return nil end
    local why = {}
    if needSell then why[#why + 1] = free == 0 and "bags full" or (free .. " bag slots left") end
    if needRepair then why[#why + 1] = ("gear at %d%%"):format(dur * 100) end
    return needRepair, table.concat(why, ", ")
end

-- hide the sell/repair stop for a while (after a vendor visit, or when you dismiss it)
function NS.SnoozeService(minutes)
    NS.serviceSnooze = GetTime() + (minutes or 20) * 60
end

local SERVICE_Q = { id = 0, name = "Sell & repair", xp = 0 }

-- Put the service stop into the route where it adds the least time, within the
-- first few steps (full bags stop you looting quest items, so it can't wait).
function NS.AddServiceStop(route, start, inst, Leg)
    local needRepair, why = NS.ServiceNeed()
    if not why then return end
    local list = services and services[inst]
    if not list then return end
    local best, bestCost, bestPos
    local limit = math.min(#route + 1, 3)
    for _, sp in ipairs(list) do
        if sp.repair or not needRepair then
            for pos = 1, limit do
                local prev = (pos == 1) and start or route[pos - 1]
                local nxt = route[pos]
                local c = Leg(prev, sp) + 30
                if nxt then c = c + Leg(sp, nxt) - Leg(prev, nxt) end
                if not bestCost or c < bestCost then best, bestCost, bestPos = sp, c, pos end
            end
        end
    end
    if not best then return end
    local stop = { role = 0, kind = "service", x = best.x, y = best.y, map = best.map, mx = best.mx, my = best.my,
        work = 30, kxp = 0, who = best.who, why = why, repair = needRepair, q = SERVICE_Q }
    table.insert(route, bestPos, stop)
    return stop
end

------------------------------------------------------------------------
-- Class trainer stop (1.21.0): new ranks come every even level. After you ding one, the route gets
-- a "Train" stop at your nearest class trainer (on this continent), placed where it costs the least
-- time within the next few steps. Visiting the trainer clears it; right-click the step to put it
-- off for 30 minutes.
------------------------------------------------------------------------
local TRAIN_Q = { id = -1, name = "Class trainer", xp = 0 }
local function CharKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end

function NS.TrainPending()
    local t = NS.db and NS.db.trainAt and NS.db.trainAt[CharKey()]
    if not t then return nil end
    if NS.trainSnooze and GetTime() < NS.trainSnooze then return nil end
    return t
end
function NS.SnoozeTrainer(minutes) NS.trainSnooze = GetTime() + (minutes or 30) * 60 end

function NS.AddTrainerStop(route, start, inst, Leg)
    if NS.db.trainer == false or not NS.TrainPending() then return end
    local list = trainers and trainers[inst]
    if not list or #list == 0 then return end
    local best, bestCost, bestPos
    local limit = math.min(#route + 1, 6)
    for _, sp in ipairs(list) do
        for pos = 1, limit do
            local prev = (pos == 1) and start or route[pos - 1]
            local nxt = route[pos]
            local c = Leg(prev, sp) + 45
            if nxt then c = c + Leg(sp, nxt) - Leg(prev, nxt) end
            if not bestCost or c < bestCost then best, bestCost, bestPos = sp, c, pos end
        end
    end
    if not best then return end
    local stop = { role = 0, kind = "trainer", x = best.x, y = best.y, map = best.map, mx = best.mx, my = best.my,
        work = 45, kxp = 0, who = best.who, q = TRAIN_Q }
    table.insert(route, bestPos, stop)
    return stop
end

local tev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LEVEL_UP", "TRAINER_SHOW" }) do tev:RegisterEvent(e) end
tev:SetScript("OnEvent", function(_, event, lvl)
    if not NS.db then return end
    NS.db.trainAt = NS.db.trainAt or {}
    if event == "PLAYER_LEVEL_UP" then
        lvl = tonumber(lvl) or UnitLevel("player")
        if lvl and lvl % 2 == 0 and lvl >= 4 then
            NS.db.trainAt[CharKey()] = lvl
            if NS.MarkDirty then NS.MarkDirty() end
        end
    elseif event == "TRAINER_SHOW" then
        -- your class trainer (a profession trainer doesn't count)
        local isClass = IsTradeskillTrainer == nil or not IsTradeskillTrainer()
        if isClass and NS.db.trainAt[CharKey()] then
            NS.db.trainAt[CharKey()] = nil
            if NS.MarkDirty then NS.MarkDirty() end
        end
    end
end)
