-- TwizQuest flight timer (1.20.0) - like Forever Flight Times, built in.
-- Times every flight you take (from -> to) and remembers it. While flying, a small bar at the top
-- of the screen counts down to landing (or counts up the first time you take a route). On the
-- flight map, hovering a destination shows how long the flight takes. /tq flights turns the bar
-- on or off; /tq flights list shows what's been timed.
local ADDON, NS = ...

local function DB()
    NS.db.flights = NS.db.flights or {}
    return NS.db.flights
end
local function On() return NS.db and NS.db.flightBar ~= false end
local function Clock(s)
    s = math.max(0, math.floor(s + 0.5))
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end
NS.Clock = Clock

-- the node you're standing at on the flight map
local function CurrentNode()
    for i = 1, (NumTaxiNodes and NumTaxiNodes() or 0) do
        if TaxiNodeGetType and TaxiNodeGetType(i) == "CURRENT" then return TaxiNodeName(i) end
    end
end

function NS.FlightTime(from, to)
    if not (NS.db and from and to) then return nil end
    return DB()[from .. " -> " .. to]
end

local pending, flight -- pending: chosen on the map; flight: in the air
local bar

local function BuildBar()
    bar = CreateFrame("StatusBar", "TwizQuestFlightBar", UIParent)
    bar:SetSize(260, 16)
    bar:SetPoint("TOP", 0, -120)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetStatusBarColor(0.30, 0.62, 0.95, 0.9)
    bar:SetMinMaxValues(0, 1); bar:SetValue(0)
    local bg = bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER")
    bar:SetMovable(true); bar:EnableMouse(true); bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", bar.StartMoving)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(); NS.db.flightBarPos = { p, rp, x, y }
    end)
    if NS.db.flightBarPos then
        local p = NS.db.flightBarPos
        bar:ClearAllPoints(); bar:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
    bar:Hide()
end

local function Land()
    if flight and flight.start then
        local took = GetTime() - flight.start
        if took > 5 and flight.from and flight.to then
            local k = flight.from .. " -> " .. flight.to
            local old = DB()[k]
            -- a flight cut short (reload, disconnect) doesn't count
            if not old then DB()[k] = math.floor(took + 0.5)
            elseif took > old * 0.6 then DB()[k] = math.floor((old * 2 + took) / 3 + 0.5) end
            if not old then NS.Print(("timed %s: %s - next time the bar counts down."):format(k, Clock(took))) end
        end
    end
    flight, pending = nil, nil
    if bar then bar:Hide() end
end

local tick = CreateFrame("Frame")
tick:SetScript("OnUpdate", function(self, el)
    self.t = (self.t or 0) + el
    if self.t < 0.2 then return end
    self.t = 0
    local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
    if onTaxi and not flight then
        flight = { from = pending and pending.from, to = pending and pending.to, start = GetTime() }
        pending = nil
    elseif not onTaxi and flight then
        Land()
    end
    if not flight then
        if pending and GetTime() - pending.at > 30 then pending = nil end -- never took off
        if not pending then self:Hide() end
        return
    end
    if not On() then if bar then bar:Hide() end; return end
    if not bar then BuildBar() end
    local known = NS.FlightTime(flight.from, flight.to)
    local gone = GetTime() - flight.start
    local where = flight.to and flight.to:gsub(",.*$", "") or "landing"
    if known and known > 0 then
        bar:SetValue(math.min(1, gone / known))
        bar.text:SetText(("%s  %s left"):format(where, Clock(known - gone)))
    else
        bar:SetValue(0)
        bar.text:SetText(("%s  timing this flight %s"):format(where, Clock(gone)))
    end
    bar:Show()
end)
tick:Hide()

local function Chose(i)
    pending = { from = CurrentNode(), to = TaxiNodeName and TaxiNodeName(i), at = GetTime() }
    tick:Show()
end
if hooksecurefunc and TakeTaxiNode then hooksecurefunc("TakeTaxiNode", function(i) pcall(Chose, i) end) end

-- hovering a destination on the flight map: add the time
local function AddTime(tip, i)
    if not (tip and i and NS.db) then return end
    local t = NS.FlightTime(CurrentNode(), TaxiNodeName(i))
    if t then tip:AddLine(("TwizQuest: %s flight"):format(Clock(t)), 0.4, 0.8, 1); tip:Show() end
end
if hooksecurefunc and TaxiNodeOnButtonEnter then
    hooksecurefunc("TaxiNodeOnButtonEnter", function(button) pcall(AddTime, GameTooltip, button and button:GetID()) end)
end
local hookedPins
local function HookPins()
    if hookedPins or not FlightPointPinMixin then return end
    hookedPins = true
    hooksecurefunc(FlightPointPinMixin, "OnMouseEnter", function(pin)
        local d = pin and pin.taxiNodeData
        if d and d.slotIndex then pcall(AddTime, GameTooltip, d.slotIndex) end
    end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "TAXIMAP_OPENED" }) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "ADDON_LOADED" and a1 == "Blizzard_FlightMap" then pcall(HookPins)
    elseif event == "TAXIMAP_OPENED" then pcall(HookPins)
    elseif event == "PLAYER_ENTERING_WORLD" then
        if UnitOnTaxi and UnitOnTaxi("player") then tick:Show() end
    end
end)

function NS.FlightsCmd(rest)
    if rest == "list" then
        local keys = {}
        for k in pairs(DB()) do keys[#keys + 1] = k end
        table.sort(keys)
        if #keys == 0 then NS.Print("no flights timed yet - take one and it's remembered."); return end
        NS.Print(("%d flights timed:"):format(#keys))
        for _, k in ipairs(keys) do print(("   %s  %s"):format(Clock(DB()[k]), k)) end
        return
    end
    NS.db.flightBar = NS.db.flightBar == false
    NS.Print("flight timer bar " .. (NS.db.flightBar and "on" or "off") .. " (flights are still timed; /tq flights list)")
end
NS._flight = { Chose = Chose, Land = Land, tick = tick }
