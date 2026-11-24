-- TwizQuest minimap line (1.21.0): a dotted line on the minimap from you toward step 1, redrawn as
-- you move. Uses HereBeDragons-Pins (comes with Questie), which places the dots and handles the
-- minimap's zoom, indoor/outdoor size and rotation. /tq line turns it on or off.
local ADDON, NS = ...

local SPACING = 18   -- yards between dots
local MAX_DOTS = 14  -- about 250 yards of line (the minimap shows less than that)
local dots = {}
local Pins
local owner = {}     -- the "ref" HBD-Pins files our dots under

local function On() return NS.db and NS.db.miniLine ~= false end

local function Dot(i)
    if dots[i] then return dots[i] end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(5, 5)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    if t.SetMask then pcall(t.SetMask, t, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end -- round
    t:SetVertexColor(0.40, 0.87, 1, 0.95)
    f.tex = t
    dots[i] = f
    return f
end

local function Clear(from)
    if not Pins then return end
    for i = from or 1, #dots do
        if dots[i].placed then Pins:RemoveMinimapIcon(owner, dots[i]); dots[i].placed = false end
    end
end

local function Draw()
    if not Pins then Pins = LibStub and LibStub("HereBeDragons-Pins-2.0", true) end
    if not Pins then return end
    local plan = NS._plan and NS._plan()
    local s = plan and plan.route and plan.route[1]
    if not (On() and s and s.x) then Clear(); return end
    local px, py, inst = NS.PlayerPos()
    if not px or (plan.inst and inst ~= plan.inst) then Clear(); return end
    local d = NS.Dist(px, py, s.x, s.y)
    if d < SPACING * 1.5 then Clear(); return end
    local n = math.min(MAX_DOTS, math.floor(d / SPACING))
    for i = 1, n do
        local f = i * SPACING / d
        local x, y = px + (s.x - px) * f, py + (s.y - py) * f
        local dot = Dot(i)
        dot.tex:SetAlpha(1 - (i - 1) / (MAX_DOTS + 4)) -- fades with distance
        Pins:AddMinimapIconWorld(owner, dot, inst, x, y, false)
        dot.placed = true
    end
    Clear(n + 1)
end
NS.DrawMiniLine = Draw

local tick = CreateFrame("Frame")
tick:SetScript("OnUpdate", function(self, el)
    self.t = (self.t or 0) + el
    if self.t < 0.5 then return end
    self.t = 0
    pcall(Draw)
end)

function NS.LineCmd()
    NS.db.miniLine = NS.db.miniLine == false
    NS.Print("minimap line to step 1 " .. (NS.db.miniLine and "on" or "off"))
    pcall(Draw)
end
