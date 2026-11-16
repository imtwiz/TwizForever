-- TwizQuest planner: finds quests you can do, estimates time and XP for
-- each, then builds the order of pick-ups, objectives and turn-ins that gives
-- the most XP per hour over the next N minutes.
local ADDON, NS = ...

local R = 150 -- yards: how close spawns must be to count as one hunting area

------------------------------------------------------------------------
-- Spreading the work over frames so the game never hitches
------------------------------------------------------------------------
local co, sliceStart
local clock = debugprofilestop or function() return GetTime() * 1000 end

local function Yield()
    if co and coroutine.running() == co and clock() - sliceStart > 6 then
        coroutine.yield()
    end
end
NS.Yield = Yield

------------------------------------------------------------------------
-- Points and hunting areas
------------------------------------------------------------------------
local function AddSpawns(spawns, inst, out, weight)
    if type(spawns) ~= "table" then return end
    for areaId, list in pairs(spawns) do
        if type(list) == "table" then
            for _, c in ipairs(list) do
                local x, y = c[1], c[2]
                if type(x) == "number" and type(y) == "number" and x > 0 and y > 0 then
                    local wx, wy, i, map = NS.World(areaId, x, y)
                    if wx and i == inst then
                        out[#out + 1] = { x = wx, y = wy, map = map, mx = x, my = y, w = weight or 1 }
                        if #out >= 600 then return end
                    end
                end
            end
        end
    end
end

local function Nearest(points, rx, ry)
    local best, bd
    for _, p in ipairs(points) do
        local d = NS.Dist(p.x, p.y, rx, ry)
        if not bd or d < bd then best, bd = p, d end
    end
    return best, bd
end

-- Pick the densest hunting area, preferring ones closer to (rx, ry).
local function Area(points, rx, ry)
    if #points == 0 then return nil end
    if #points == 1 then
        local p = points[1]
        return { x = p.x, y = p.y, map = p.map, mx = p.mx, my = p.my, spacing = 60, n = 1 }
    end
    local step = math.max(1, math.floor(#points / 100))
    local bestScore, bestC
    for i = 1, #points, step do
        local c = points[i]
        local nw = 0
        for _, p in ipairs(points) do
            if NS.Dist(c.x, c.y, p.x, p.y) <= R then nw = nw + p.w end
        end
        local score = nw / (1 + NS.Dist(c.x, c.y, rx, ry) / 700)
        if not bestScore or score > bestScore then bestScore, bestC = score, c end
    end
    local sx, sy, sw = 0, 0, 0
    for _, p in ipairs(points) do
        if NS.Dist(bestC.x, bestC.y, p.x, p.y) <= R then
            sx, sy, sw = sx + p.x * p.w, sy + p.y * p.w, sw + p.w
        end
    end
    local cx, cy = sx / sw, sy / sw
    local rep = Nearest(points, cx, cy)
    local spacing = math.sqrt(math.pi * R * R / math.max(sw, 1))
    spacing = math.max(15, math.min(spacing, 150))
    return { x = cx, y = cy, map = rep.map, mx = rep.mx, my = rep.my, spacing = spacing, n = sw }
end

------------------------------------------------------------------------
-- Estimating one objective
------------------------------------------------------------------------
local DEFAULT_NEED = { monster = 8, killcredit = 8, item = 8, object = 5 }

local function MobInfo(npc)
    local lo, hi = NS.N(npc, "minLevel"), NS.N(npc, "maxLevel")
    local rank = NS.N(npc, "rank") or 0
    local lvl = ((lo or 0) + (hi or lo or 0)) / 2
    return (lvl > 0) and lvl or UnitLevel("player"), (rank == 1 or rank == 2 or rank == 3)
end

-- In a group, elites go down about twice as fast and elite quests are fair game.
function NS.Grouped()
    return (GetNumGroupMembers and GetNumGroupMembers() or 0) > 1
end

local function KillWork(kills, mobLevel, elite, spacing)
    local L = NS.db.learn
    local me = UnitLevel("player")
    local lf = math.max(0.6, math.min(2.5, 1 + 0.12 * (mobLevel - me)))
    if elite then lf = lf * (NS.Grouped() and 1.5 or 3) end
    local per = L.secPerKill * lf + L.restPerKill + spacing * L.detour / L.runSpeed
    return kills * per, kills * NS.KillXP(me, mobLevel, elite)
end

-- obj = { type = "monster"|"killcredit"|"item"|"object"|"event", ids = {...}, text, need }
-- Returns a stop (without quest fields) or nil if we can't place it.
local function EstimateObjective(obj, inst, rx, ry)
    local points = {}
    local stop = { role = 2, kind = obj.type, need = obj.need, text = obj.text }

    if obj.type == "monster" or obj.type == "killcredit" then
        for _, npc in ipairs(obj.ids) do AddSpawns(NS.N(npc, "spawns"), inst, points) end
        local area = Area(points, rx, ry)
        if not area then return nil end
        local lvl, elite = MobInfo(obj.ids[1])
        stop.elite = elite
        stop.work, stop.kxp = KillWork(obj.need, lvl, elite, area.spacing)
        stop.name = NS.N(obj.ids[1], "name")
        for k, v in pairs(area) do stop[k] = v end
        return stop
    end

    if obj.type == "object" then
        for _, o in ipairs(obj.ids) do AddSpawns(NS.O(o, "spawns"), inst, points) end
        local area = Area(points, rx, ry)
        if not area then return nil end
        local L = NS.db.learn
        stop.work = obj.need * (5 + area.spacing * L.detour / L.runSpeed)
        stop.kxp = 0
        stop.name = NS.O(obj.ids[1], "name")
        for k, v in pairs(area) do stop[k] = v end
        return stop
    end

    if obj.type == "item" then
        local item = obj.ids[1]
        stop.name = NS.I(item, "name")
        local droppers = NS.I(item, "npcDrops")
        if type(droppers) == "table" and #droppers > 0 then
            local rateSum, rateW = 0, 0
            for _, npc in ipairs(droppers) do
                local rate = 35
                local ok, dr = pcall(NS.bridgeDropRate, item, npc)
                if ok and type(dr) == "table" and tonumber(dr[1]) then rate = tonumber(dr[1]) end
                rate = math.max(3, math.min(rate, 100))
                local before = #points
                AddSpawns(NS.N(npc, "spawns"), inst, points, rate / 35)
                if #points > before then rateSum, rateW = rateSum + rate, rateW + 1 end
            end
            local area = Area(points, rx, ry)
            if area then
                local rate = (rateW > 0) and (rateSum / rateW) or 35
                local kills = math.min(obj.need * 8, math.ceil(obj.need / (rate / 100)))
                local lvl, elite = MobInfo(droppers[1])
                stop.elite = elite
                stop.kills = kills
                stop.work, stop.kxp = KillWork(kills, lvl, elite, area.spacing)
                stop.dropper = NS.N(droppers[1], "name")
                for k, v in pairs(area) do stop[k] = v end
                return stop
            end
        end
        local objs = NS.I(item, "objectDrops")
        if type(objs) == "table" and #objs > 0 then
            for _, o in ipairs(objs) do AddSpawns(NS.O(o, "spawns"), inst, points) end
            local area = Area(points, rx, ry)
            if area then
                local L = NS.db.learn
                stop.work = obj.need * (5 + area.spacing * L.detour / L.runSpeed)
                stop.kxp = 0
                stop.kind = "loot"
                for k, v in pairs(area) do stop[k] = v end
                return stop
            end
        end
        local vendors = NS.I(item, "vendors")
        if type(vendors) == "table" and #vendors > 0 then
            for _, v in ipairs(vendors) do AddSpawns(NS.N(v, "spawns"), inst, points) end
            local p = Nearest(points, rx, ry)
            if p then
                stop.kind, stop.work, stop.kxp = "buy", 15, 0
                stop.vendor = NS.N(vendors[1], "name")
                stop.x, stop.y, stop.map, stop.mx, stop.my = p.x, p.y, p.map, p.mx, p.my
                return stop
            end
        end
        return nil
    end

    if obj.type == "event" then
        AddSpawns(obj.spawns, inst, points)
        local p = Nearest(points, rx, ry)
        if not p then return nil end
        stop.work, stop.kxp = 10, 0
        stop.x, stop.y, stop.map, stop.mx, stop.my = p.x, p.y, p.map, p.mx, p.my
        return stop
    end
    return nil
end

------------------------------------------------------------------------
-- Reading a quest's objectives from Questie, matched to your quest log
------------------------------------------------------------------------
local function DBObjectives(id)
    local list = { monster = {}, item = {}, object = {}, event = {} }
    local raw = NS.Q(id, "objectives")
    if type(raw) == "table" then
        for _, c in ipairs(type(raw[1]) == "table" and raw[1] or {}) do
            if type(c) == "table" and c[1] then table.insert(list.monster, { type = "monster", ids = { c[1] }, text = c[2] }) end
        end
        for _, c in ipairs(type(raw[2]) == "table" and raw[2] or {}) do
            if type(c) == "table" and c[1] then table.insert(list.object, { type = "object", ids = { c[1] }, text = c[2] }) end
        end
        for _, c in ipairs(type(raw[3]) == "table" and raw[3] or {}) do
            if type(c) == "table" and c[1] then table.insert(list.item, { type = "item", ids = { c[1] }, text = c[2] }) end
        end
        for _, c in ipairs(type(raw[5]) == "table" and raw[5] or {}) do
            if type(c) == "table" and type(c[1]) == "table" and #c[1] > 0 then
                table.insert(list.monster, { type = "killcredit", ids = c[1], text = c[3] })
            end
        end
    end
    local trig = NS.Q(id, "triggerEnd")
    if type(trig) == "table" and type(trig[2]) == "table" then
        table.insert(list.event, { type = "event", spawns = trig[2], text = trig[1] })
    end
    return list
end

-- For quests in your log: what's still left to do, with real counts.
local function LogObjectives(id)
    local db = DBObjectives(id)
    local out, unknown = {}, 0
    local unknownTexts = {}
    local ok, log = pcall(C_QuestLog.GetQuestObjectives, id)
    if not ok or type(log) ~= "table" or #log == 0 then
        for _, t in pairs(db) do for _, o in ipairs(t) do
            o.need = o.need or DEFAULT_NEED[o.type] or 1; out[#out + 1] = o
        end end
        return out, unknown
    end
    local queues = { monster = 1, item = 1, object = 1, event = 1 }
    for _, lo in ipairs(log) do
        local t = lo.type
        if t == "reputation" or t == "player" or t == "progressbar" then t = nil end
        if t == "log" then t = "event" end
        local entry, key
        if t and db[t] then
            entry = db[t][queues[t]]
            key = t:sub(1, 1) .. queues[t]
            queues[t] = queues[t] + 1
        end
        if entry then entry._k = key end
        if not NS.safe(lo.finished) then
            local need = (tonumber(NS.safe(lo.numRequired)) or 1) - (tonumber(NS.safe(lo.numFulfilled)) or 0)
            if entry and need > 0 then
                entry.need = need
                entry.text = NS.safe(lo.text) or entry.text
                out[#out + 1] = entry
            elseif need > 0 then
                unknown = unknown + 1
                unknownTexts[#unknownTexts + 1] = NS.safe(lo.text)
            end
        end
    end
    return out, unknown, unknownTexts
end

------------------------------------------------------------------------
-- Building a quest: pick-up, objectives, turn-in
------------------------------------------------------------------------
local function Starters(id, inst)
    local pts = {}
    local by = NS.Q(id, "startedBy")
    if type(by) ~= "table" then return pts end
    for _, npc in ipairs(by[1] or {}) do
        local before = #pts
        AddSpawns(NS.N(npc, "spawns"), inst, pts)
        for i = before + 1, #pts do pts[i].who = NS.N(npc, "name") end
    end
    for _, o in ipairs(by[2] or {}) do
        local before = #pts
        AddSpawns(NS.O(o, "spawns"), inst, pts)
        for i = before + 1, #pts do pts[i].who = NS.O(o, "name") end
    end
    return pts
end

local function Finishers(id, inst)
    local pts = {}
    local by = NS.Q(id, "finishedBy")
    if type(by) ~= "table" then return pts end
    for _, npc in ipairs(by[1] or {}) do
        local before = #pts
        AddSpawns(NS.N(npc, "spawns"), inst, pts)
        for i = before + 1, #pts do pts[i].who = NS.N(npc, "name") end
    end
    for _, o in ipairs(by[2] or {}) do
        local before = #pts
        AddSpawns(NS.O(o, "spawns"), inst, pts)
        for i = before + 1, #pts do pts[i].who = NS.O(o, "name") end
    end
    return pts
end

local function PointStop(p, role, work)
    return { role = role, x = p.x, y = p.y, map = p.map, mx = p.mx, my = p.my,
             work = work, kxp = 0, who = p.who }
end

-- Quest items already in the bank: take them off what's left to collect
-- and add a "get it from the bank" stop.
local function BankStop(q, o, inst, rx, ry)
    local item = o.ids and o.ids[1]
    local inBank = item and NS.BankCount(item) or 0
    if inBank <= 0 or (o.need or 0) <= 0 then return end
    local bank = NS.NearestBank(inst, rx, ry)
    if not bank then return end
    local take = math.min(inBank, o.need)
    o.need = o.need - take
    return { role = 1, kind = "bank", x = bank.x, y = bank.y, map = bank.map, mx = bank.mx, my = bank.my,
             work = 20, kxp = 0, need = take, name = NS.I(item, "name") or o.text }
end

-- A quest started by an item you're carrying (or have in the bank).
local function ItemStart(id, inst, px, py)
    local by = NS.Q(id, "startedBy")
    for _, item in ipairs(type(by) == "table" and by[3] or {}) do
        if NS.BagCount(item) > 0 then
            return { role = 1, kind = "useitem", x = px, y = py, work = 5, kxp = 0,
                     name = NS.I(item, "name") }
        end
        if NS.BankCount(item) > 0 then
            local bank = NS.NearestBank(inst, px, py)
            if bank then
                return { role = 1, kind = "bankstart", x = bank.x, y = bank.y, map = bank.map,
                         mx = bank.mx, my = bank.my, work = 20, kxp = 0, name = NS.I(item, "name") }
            end
        end
    end
end

-- active: nil for a new quest, or { complete = bool }
local function BuildQuest(id, inst, px, py, active)
    local q = { id = id, name = NS.Q(id, "name") or ("Quest " .. id), xp = NS.QuestXP(id),
                level = NS.Q(id, "questLevel"), active = active ~= nil, stops = {} }
    if q.xp <= 0 then return nil end
    local rx, ry = px, py

    if not active then
        local p, d = Nearest(Starters(id, inst), px, py)
        local s
        if p and d <= NS.db.maxDist then
            s = PointStop(p, 1, 8)
            s.kind = "pickup"
        else
            s = ItemStart(id, inst, px, py)   -- started by an item you have
            if not s then return nil end
        end
        q.stops[#q.stops + 1] = s
        rx, ry = s.x, s.y
    end

    local extra = 0
    -- party members on this quest who still need kills or drops: credit is shared,
    -- so staying to help them is worth planning for
    local pneed = active and NS.PartyNeed and NS.PartyNeed(id)
    if NS.groupMode and NS.GroupWho then
        -- group plan: each member who gets this quest's XP counts in full
        q.groupN = NS.GroupWho(id, active)
        q.pw = 1 + q.groupN
    elseif NS.PartyHas then
        local n = NS.PartyHas(id)
        q.party = n
        q.pw = 1 + 0.25 * math.min(2, n)   -- doing a quest together beats doing it alone
    end
    local todo = {}   -- objectives still to do that we can't put on the map
    if not (active and active.complete) or pneed then
        local objs, unknown, unknownTexts
        if active and active.complete then
            objs, unknown = {}, 0
        elseif active then
            objs, unknown, unknownTexts = LogObjectives(id)
            for _, t in ipairs(unknownTexts or {}) do todo[#todo + 1] = t end
        else
            objs, unknown = {}, 0
            for _, t in pairs(DBObjectives(id)) do
                for _, o in ipairs(t) do o.need = DEFAULT_NEED[o.type] or 1; objs[#objs + 1] = o end
            end
        end
        if pneed then
            local have = {}
            for _, o in ipairs(objs) do
                local pn = o._k and pneed[o._k]
                if pn and pn.need > (o.need or 0) then o.need, o.help = pn.need, pn.who end
                if o._k then have[o._k] = true end
            end
            local db = DBObjectives(id)
            for key, pn in pairs(pneed) do
                if not have[key] then
                    local t = (key:sub(1, 1) == "m") and "monster" or "item"
                    local e = db[t] and db[t][tonumber(key:sub(2))]
                    if e then e.need, e.help, e._k = pn.need, pn.who, key; objs[#objs + 1] = e end
                end
            end
        end
        for _, o in ipairs(objs) do
            if o.type == "item" and not o.help then
                local b = BankStop(q, o, inst, rx, ry)
                if b then q.stops[#q.stops + 1] = b end
            end
            local s = (o.need or 0) > 0 and EstimateObjective(o, inst, rx, ry) or nil
            if s and o.help then s.help = o.help end
            if (o.need or 0) <= 0 then
                -- the bank covers it all
            elseif s then
                if s.elite and not NS.db.elites and not NS.Grouped() and not active then return nil end
                q.stops[#q.stops + 1] = s
                rx, ry = s.x, s.y
            elseif active then
                todo[#todo + 1] = o.text or "an objective"   -- can't place it: still has to be done first
            else
                return nil              -- can't estimate a new quest reliably
            end
        end
    end
    -- never send you to turn in a quest that isn't done: list what's left first
    if active and not active.complete and #todo > 0 then
        local names = {}
        for _, t in ipairs(todo) do if t and t ~= "" then names[#names + 1] = t end end
        q.stops[#q.stops + 1] = { role = 2, kind = "todo", x = rx, y = ry, work = 300 * #todo, kxp = 0,
            text = "Finish: " .. (#names > 0 and table.concat(names, ", ") or "the remaining objectives"), noWay = true }
    end

    local p = Nearest(Finishers(id, inst), rx, ry)
    if not p then return nil end
    local s = PointStop(p, 3, 8 + extra)
    s.kind = "turnin"
    q.stops[#q.stops + 1] = s
    for _, st in ipairs(q.stops) do st.q = q end
    return q
end

------------------------------------------------------------------------
-- Finding candidate quests
------------------------------------------------------------------------
local function QuestLog()
    local active, inLog = {}, {}
    local n = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        local id = info and NS.safe(info.questID)
        if id and id > 0 and not NS.safe(info.isHeader) then
            inLog[id] = true
            local failed = C_QuestLog.IsFailed and C_QuestLog.IsFailed(id)
            if not failed then
                -- complete only if the game says so AND no objective is still unfinished
                local complete = C_QuestLog.IsComplete(id) and true or false
                if complete then
                    local ok, objs = pcall(C_QuestLog.GetQuestObjectives, id)
                    for _, o in ipairs(ok and type(objs) == "table" and objs or {}) do
                        if not NS.safe(o.finished) and (tonumber(NS.safe(o.numFulfilled)) or 0) < (tonumber(NS.safe(o.numRequired)) or 1) then
                            complete = false
                        end
                    end
                end
                active[#active + 1] = { id = id, complete = complete }
            end
        end
    end
    return active, inLog
end

local function Excluded(DB, id)
    for _, fn in ipairs({ "IsDungeonQuest", "IsRaidQuest", "IsGroupQuest", "IsPvPQuest", "IsRepeatable" }) do
        if DB[fn] then
            local ok, v = pcall(DB[fn], id)
            if ok and v then return true end
        end
    end
    return false
end

local function Candidates(inst, px, py)
    local B = NS.Bridge()
    local DB = B.DB
    local me = UnitLevel("player")
    local gray = NS.GrayLevel(me)
    local list = {}
    local active, inLog = QuestLog()
    NS.PrepareBankers()   -- may pause between frames; must happen outside any pcall
    if NS.PrepareServices then NS.PrepareServices() end
    NS.skipped, NS.firstSkip = 0, nil

    -- one quest with odd data must never stop the whole plan
    local function Try(id, a)
        local ok, q = pcall(BuildQuest, id, inst, px, py, a)
        if ok then return q end
        NS.skipped = NS.skipped + 1
        if not NS.firstSkip then NS.firstSkip = ("quest %d: %s"):format(id, tostring(q)) end
    end

    for _, a in ipairs(active) do
        local q = Try(a.id, a)
        if q then list[#list + 1] = q end
        Yield()
    end

    local free = (C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept() or 25) - #active
    local n = 0
    for id in pairs(DB.QuestPointers or {}) do
        n = n + 1
        if n % 40 == 0 then Yield() end
        if not inLog[id] then
            local rl = NS.Q(id, "requiredLevel") or 0
            local ql = NS.Q(id, "questLevel") or rl
            if ql == -1 then ql = me end
            if rl <= me and ql <= me + NS.db.maxAbove and ql > gray and not Excluded(DB, id)
                and not (NS.IsSkipped and NS.IsSkipped(id)) then
                local ok, doable = pcall(DB.IsDoable, id)
                if ok and doable then
                    local q = Try(id, nil)
                    if q then list[#list + 1] = q end
                end
            end
        end
    end
    -- following a party member's group plan: their quests come first (none of yours are hidden)
    local gp = NS.groupPlan
    if gp and gp.set then
        for _, q in ipairs(list) do
            if gp.set[q.id] then q.pw = (q.pw or 1) * 1.5 end
        end
    end
    return list, math.max(0, free)
end

------------------------------------------------------------------------
-- Routing
------------------------------------------------------------------------
local function Leg(a, b)
    return NS.TravelTime(NS.Dist(a.x, a.y, b.x, b.y))
end

-- Rested XP doubles kill XP until the rested pool runs out, so while you're
-- rested, kill-heavy quests are worth more. NS.restPool is read once per plan.
local function Totals(route, start)
    local t, xp, prev = 0, 0, start
    local rest = NS.restPool or 0
    for _, s in ipairs(route) do
        t = t + Leg(prev, s) + s.work
        local k = s.kxp or 0
        local bonus = math.min(k, rest)
        rest = rest - bonus
        xp = xp + k + bonus
        if s.role == 3 then xp = xp + s.q.xp * (s.q.pw or 1) end
        prev = s
    end
    return t, xp
end

local function AddCost(route, pos, s, start)
    local prev = (pos == 1) and start or route[pos - 1]
    local nxt = route[pos]
    local c = Leg(prev, s) + s.work
    if nxt then c = c + Leg(s, nxt) - Leg(prev, nxt) end
    return c
end

local function BestPos(route, s, lo, start)
    local bestP, bestC
    for p = lo, #route + 1 do
        local c = AddCost(route, p, s, start)
        if not bestC or c < bestC then bestP, bestC = p, c end
    end
    return bestP
end

local function IndexOf(route, s)
    for i, v in ipairs(route) do if v == s then return i end end
end

-- Insert all of q's stops in their cheapest places, keeping
-- pick-up -> objectives -> turn-in order.
local function InsertQuest(route, q, start)
    local r = {}
    for i, v in ipairs(route) do r[i] = v end
    for _, s in ipairs(q.stops) do
        if s.role == 1 then table.insert(r, BestPos(r, s, 1, start), s) end
    end
    local lo = 1
    for _, s in ipairs(q.stops) do
        if s.role == 1 then lo = math.max(lo, (IndexOf(r, s) or 0) + 1) end
    end
    for _, s in ipairs(q.stops) do
        if s.role == 2 then table.insert(r, BestPos(r, s, lo, start), s) end
    end
    for _, s in ipairs(q.stops) do
        if s.role == 3 then
            local last = lo - 1
            for _, o in ipairs(q.stops) do
                if o.role ~= 3 then last = math.max(last, IndexOf(r, o) or 0) end
            end
            table.insert(r, BestPos(r, s, last + 1, start), s)
        end
    end
    return r
end

-- Move single stops to cheaper spots (keeping each quest's order).
local function Improve(route, start)
    for _ = 1, 2 do
        local improved = false
        for i = 1, #route do
            local s = route[i]
            local before = Totals(route, start)
            table.remove(route, i)
            local lo, hi = 1, #route + 1
            for j, o in ipairs(route) do
                if o.q == s.q then
                    if o.role < s.role then lo = math.max(lo, j + 1)
                    elseif o.role > s.role then hi = math.min(hi, j) end
                end
            end
            local bestP, bestC
            for p = lo, hi do
                local c = AddCost(route, p, s, start)
                if not bestC or c < bestC then bestP, bestC = p, c end
            end
            table.insert(route, bestP or i, s)
            if Totals(route, start) < before - 0.5 then improved = true end
            Yield()
        end
        if not improved then break end
    end
end

local function BuildRoute(cands, free, start)
    local H = NS.db.horizon * 60
    for _, q in ipairs(cands) do
        local t, xp = Totals(InsertQuest({}, q, start), start)
        q.rate = (t > 0) and xp / t or 0
    end
    table.sort(cands, function(a, b) return a.rate > b.rate end)
    local pool = {}
    for i = 1, math.min(#cands, 80) do pool[i] = cands[i] end

    local route, T, X, picked = {}, 0, 0, 0
    while true do
        local best, bestR, bestRate, bestT, bestX
        for i, q in ipairs(pool) do
            if q.active or picked < free then
                local r = InsertQuest(route, q, start)
                local t, x = Totals(r, start)
                if t <= H and t > 0 then
                    local rate = x / t
                    if not bestRate or rate > bestRate then
                        best, bestR, bestRate, bestT, bestX = i, r, rate, t, x
                    end
                end
            end
            Yield()
        end
        if not best then break end
        local cur = (T > 0) and X / T or 0
        if T >= H * 0.5 and bestRate < cur * 0.97 then break end
        local q = table.remove(pool, best)
        if not q.active then picked = picked + 1 end
        route, T, X = bestR, bestT, bestX
    end
    -- synced with your party: never leave a quest from your log out of the route;
    -- the leftovers go in where they cost least, after the best-XP ones
    if NS.KeepAllQuests and NS.KeepAllQuests() then
        local inRoute = {}
        for _, st in ipairs(route) do if st.q then inRoute[st.q] = true end end
        for _, q in ipairs(cands) do
            if q.active and not inRoute[q] then route = InsertQuest(route, q, start) end
        end
    end
    Improve(route, start)
    return route
end

------------------------------------------------------------------------
-- Public: NS.Plan() runs in the background and calls NS.OnPlan(result)
------------------------------------------------------------------------
local runner = CreateFrame("Frame")
runner:Hide()
runner:SetScript("OnUpdate", function(self)
    if not co then self:Hide(); return end
    sliceStart = clock()
    local thread = co
    local ok, err = coroutine.resume(co)
    if not ok then
        co = nil; self:Hide()
        local stack = ""
        if debugstack then
            local okS, st = pcall(debugstack, thread)
            if okS and st then stack = st end
        end
        if NS.db then NS.db.lastError = { msg = tostring(err), stack = stack, at = time and time() or 0 } end
        NS.Print("planning failed: " .. tostring(err) .. "  (/tq error for details)")
        if NS.OnPlan then NS.OnPlan(nil, tostring(err)) end
    elseif coroutine.status(co) == "dead" then
        co = nil; self:Hide()
    end
end)

function NS.IsPlanning() return co ~= nil end

-- full = true: search every quest again. false: re-order the quests found
-- last time from where you're standing now (cheap; used while you move).
function NS.Plan(full)
    if co then return end
    local B, why = NS.Bridge()
    if not B then
        if NS.OnPlan then NS.OnPlan(nil, why) end
        return
    end
    NS.bridgeDropRate = B.DB.GetItemDroprate
    co = coroutine.create(function()
        local px, py, inst = NS.PlayerPos()
        if not px then
            if NS.OnPlan then NS.OnPlan(nil, "can't tell where you are here") end
            return
        end
        local start = { x = px, y = py }
        NS.restPool = (GetXPExhaustion and GetXPExhaustion()) or 0
        local cache = NS.cache
        local cands, free
        if full or not cache or cache.inst ~= inst then
            cands, free = Candidates(inst, px, py)
            NS.cache = { cands = cands, free = free, inst = inst, at = GetTime() }
        else
            cands, free = cache.cands, cache.free
        end
        local route = BuildRoute(cands, free, start)
        local service = NS.AddServiceStop and NS.AddServiceStop(route, start, inst, Leg)
        local t, prev, xp = 0, start, 0
        local rest = NS.restPool or 0
        for _, s in ipairs(route) do
            s.dist = NS.Dist(prev.x, prev.y, s.x, s.y)
            s.travel = Leg(prev, s)
            t = t + s.travel + s.work
            local k = s.kxp or 0
            s.restBonus = math.min(k, rest)
            rest = rest - s.restBonus
            xp = xp + k + s.restBonus + ((s.role == 3) and s.q.xp or 0)
            s.eta, s.cumXP = t, xp
            prev = s
        end
        -- quests in your log that didn't make the route: not worth their slot
        local inRoute = {}
        for _, s in ipairs(route) do if s.q then inRoute[s.q] = true end end
        local planRate = (t > 0) and xp / t or 0
        local gray = NS.GrayLevel(UnitLevel("player"))
        local drop = {}
        local keepAll = NS.KeepAllQuests and NS.KeepAllQuests()
        for _, q in ipairs(keepAll and {} or cands) do
            -- judged on its own: XP/hour if you did just this quest from here
            local slow = planRate > 0 and (q.rate or 0) < planRate * 0.35
            if q.active and (slow or not inRoute[q]) then
                local lvl = q.level or 0
                if lvl > 0 and lvl <= gray and (slow or not inRoute[q]) then
                    drop[#drop + 1] = { id = q.id, name = q.name, why = ("gray - %s xp/hr on its own"):format(NS.FormatNum((q.rate or 0) * 3600)) }
                elseif slow then
                    drop[#drop + 1] = { id = q.id, name = q.name,
                        why = ("%s xp/hr vs your plan's %s"):format(NS.FormatNum((q.rate or 0) * 3600), NS.FormatNum(planRate * 3600)) }
                end
            end
        end
        local groupXP = xp
        if NS.groupMode then
            for _, s in ipairs(route) do
                if s.role == 3 and s.q.groupN then groupXP = groupXP + s.q.xp * s.q.groupN end
            end
        end
        local result = { route = route, time = t, xp = xp, rate = (t > 0) and xp / t * 3600 or 0,
                         group = NS.groupMode and { rate = (t > 0) and groupXP / t * 3600 or 0,
                             members = (NS.SyncedCount and NS.SyncedCount() or 0) + 1,
                             from = NS.groupPlan and NS.groupPlan.from } or nil,
                         candidates = #cands, at = GetTime(), x = px, y = py, inst = inst, full = full,
                         skipped = NS.skipped or 0, drop = drop, service = service, rested = NS.restPool or 0,
                         logFull = (free or 0) <= 0 }
        if (NS.skipped or 0) > 0 and NS.db then
            NS.db.lastError = { msg = ("%d quest(s) skipped; first: %s"):format(NS.skipped, NS.firstSkip or "?"),
                                stack = "", at = time and time() or 0 }
        end
        if NS.PartyStep and route[1] then NS.PartyStep(route[1]) end
        if NS.groupMode and not NS.groupPlan and NS.SendGroupPlan then NS.SendGroupPlan(route) end
        if NS.OnPlan then NS.OnPlan(result) end
    end)
    runner:Show()
end
