-- TwizQuest travel (1.21.0): hearthstone and flights in the plan.
--  * Learns where your hearthstone is set (when you set it at an innkeeper, or the first time you
--    hearth there) and, when it's off cooldown, uses it for the first leg if that's faster.
--  * Learns where flight masters are (when you open a flight map) and, with the flight times
--    TwizQuest has recorded, flies a leg when that beats running.
--  * At an innkeeper whose inn is close to your next steps (and your hearth is far from them),
--    it suggests setting your hearth there - that also means full rested XP when you log out.
local ADDON, NS = ...

local HEARTHSTONE = 6948
local HEARTH_SPELL = 8690
local HEARTH_COST = 10 + 20   -- cast + loading
local FLIGHT_COST = 25        -- talk to the flight master, take off, land

local function DB() return NS.db end
local function Bridge() local B = NS.Bridge and NS.Bridge(); return B end

------------------------------------------------------------------------
-- hearthstone
------------------------------------------------------------------------
function NS.HearthReady()
    if not (GetItemCount and GetItemCount(HEARTHSTONE) > 0) then return false end
    local start, dur
    if C_Container and C_Container.GetItemCooldown then start, dur = C_Container.GetItemCooldown(HEARTHSTONE)
    elseif GetItemCooldown then start, dur = GetItemCooldown(HEARTHSTONE) end
    if not start or start == 0 or not dur then return true end
    return start + dur - GetTime() < 60
end

local function BindName() return GetBindLocation and GetBindLocation() or nil end

-- your hearth spot, if TwizQuest knows where it is (and it's still the same inn)
function NS.Bind()
    local b = DB() and DB().bind
    if not b or not b.x then return nil end
    local name = BindName()
    if name and b.name and name ~= b.name then return nil end -- moved your hearth somewhere new
    return b
end

local function RememberBind(why)
    local x, y, inst = NS.PlayerPos()
    if not x then return end
    DB().bind = { name = BindName(), x = x, y = y, inst = inst }
    if why then NS.Print(("hearthstone spot learned: %s - the plan will use your hearth when it's faster."):format(BindName() or "here")) end
end
NS.RememberBind = RememberBind

------------------------------------------------------------------------
-- flight masters
------------------------------------------------------------------------
local function TaxiDB() DB().taxi = DB().taxi or {}; return DB().taxi end

local function LearnTaxiNodes()
    local B = Bridge()
    if not (B and B.HBD) then return end
    local map = GetTaxiMapID and GetTaxiMapID()
    local n = 0
    if map and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
        for _, node in ipairs(C_TaxiMap.GetAllTaxiNodes(map) or {}) do
            local pos = node.position
            if node.name and pos and pos.x then
                local wx, wy, inst = B.HBD:GetWorldCoordinatesFromZone(pos.x, pos.y, map)
                if wx then TaxiDB()[node.name] = { x = wx, y = wy, inst = inst }; n = n + 1 end
            end
        end
    end
    -- where you stand is the most exact spot for the flight master you're talking to
    for i = 1, (NumTaxiNodes and NumTaxiNodes() or 0) do
        if TaxiNodeGetType and TaxiNodeGetType(i) == "CURRENT" then
            local x, y, inst = NS.PlayerPos()
            if x then TaxiDB()[TaxiNodeName(i)] = { x = x, y = y, inst = inst }; n = n + 1 end
        end
    end
    return n
end
NS.LearnTaxiNodes = LearnTaxiNodes

------------------------------------------------------------------------
-- travel options for one leg
------------------------------------------------------------------------
local flights = {}   -- usable this plan: { from = node, to = node, time, fromName, toName }
local planInst

-- called once per plan: which recorded flights we know both ends of, in this world
function NS.PrepTravel(inst)
    planInst = inst
    wipe(flights)
    NS.hearthNow = NS.HearthReady()
    local t = DB() and DB().flights
    local nodes = DB() and DB().taxi
    if not (t and nodes) then return end
    for key, secs in pairs(t) do
        local from, to = key:match("^(.-) %-> (.-)$")
        local F, T = from and nodes[from], to and nodes[to]
        if F and T and F.inst == inst and T.inst == inst and secs and secs > 0 then
            flights[#flights + 1] = { from = F, to = T, time = secs, fromName = from:gsub(",.*$", ""), toName = to:gsub(",.*$", "") }
        end
    end
end

local function Walk(ax, ay, bx, by) return NS.TravelTime(NS.Dist(ax, ay, bx, by)) end

-- the fastest way from a to b: seconds, and how ("hearth to X" / "fly X to Y") when not on foot
function NS.TravelVia(a, b, walk)
    local best, via = walk, nil
    if a.isStart and NS.hearthNow then
        local bind = NS.Bind()
        if bind and bind.inst == planInst then
            local t = HEARTH_COST + Walk(bind.x, bind.y, b.x, b.y)
            if t < best * 0.85 then best, via = t, "hearth to " .. (bind.name or "your inn") end
        end
    end
    for _, f in ipairs(flights) do
        local t = Walk(a.x, a.y, f.from.x, f.from.y) + FLIGHT_COST + f.time + Walk(f.to.x, f.to.y, b.x, b.y)
        if t < best * 0.9 then best, via = t, ("fly %s to %s"):format(f.fromName, f.toName) end
    end
    return best, via
end

------------------------------------------------------------------------
-- events: learn the bind spot and flight masters; innkeeper suggestion
------------------------------------------------------------------------
local hearthAt, castFrom
local function AfterHearth()
    if not hearthAt or GetTime() - hearthAt > 90 then return end
    local x, y = NS.PlayerPos()
    if x and castFrom and NS.Dist(x, y, castFrom.x, castFrom.y) > 200 then
        hearthAt = nil
        local b = DB().bind
        if not (b and b.x and b.name == BindName()) then RememberBind(true) end
    end
end

local function InnkeeperHint()
    if not (C_GossipInfo and C_GossipInfo.GetOptions) then return end
    local binder = false
    for _, o in ipairs(C_GossipInfo.GetOptions() or {}) do
        local n = o.name and tostring(o.name):lower() or ""
        if o.type == "binder" or n:find("inn your home", 1, true) or n:find("make this inn", 1, true) then binder = true end
    end
    if not binder then return end
    local plan = NS._plan and NS._plan()
    local route = plan and plan.route
    if not route or #route == 0 then return end
    local x, y, inst = NS.PlayerPos()
    if not x then return end
    local cx, cy, n = 0, 0, 0
    for i = 1, math.min(6, #route) do
        local s = route[i]
        if s.x then cx, cy, n = cx + s.x, cy + s.y, n + 1 end
    end
    if n == 0 then return end
    cx, cy = cx / n, cy / n
    local near = NS.Dist(x, y, cx, cy)
    local bind = NS.Bind()
    local far = bind and bind.inst == inst and NS.Dist(bind.x, bind.y, cx, cy) or math.huge
    if near < 700 and far > near + 800 then
        NS.Print(("set your hearth here? Your next %d steps are close to this inn%s - and logging out at an inn gives full rested XP.")
            :format(n, bind and (" (your hearth is at " .. (bind.name or "?") .. ")") or ""))
    end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "HEARTHSTONE_BOUND", "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
    "TAXIMAP_OPENED", "GOSSIP_SHOW" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1, _, a3)
    if not DB() then return end
    if event == "HEARTHSTONE_BOUND" then
        C_Timer.After(0.5, function() RememberBind(true) end)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if a1 == "player" and a3 == HEARTH_SPELL then
            hearthAt = GetTime()
            local x, y = NS.PlayerPos()
            castFrom = x and { x = x, y = y } or nil
            for _, d in ipairs({ 3, 8, 15 }) do C_Timer.After(d, AfterHearth) end
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(2, AfterHearth)
    elseif event == "TAXIMAP_OPENED" then
        pcall(LearnTaxiNodes)
    elseif event == "GOSSIP_SHOW" then
        pcall(InnkeeperHint)
    end
end)
