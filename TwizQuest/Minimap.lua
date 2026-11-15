-- TwizQuest minimap button: left-click shows/hides the window, right-click
-- replans, drag to move it around the minimap. /tq minimap hides it.
local ADDON, NS = ...

local button
local function Place()
    local angle = math.rad(NS.db.minimapAngle or 200)
    local r = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function Build()
    button = CreateFrame("Button", "TwizQuestMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    icon:SetPoint("TOPLEFT", 7, -6)

    button:SetScript("OnClick", function(_, which)
        if which == "RightButton" then NS.Replan(); NS.Print("replanning...")
        else SlashCmdList.QUESTROUTE("") end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            NS.db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            Place()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("TwizQuest")
        local plan = NS._plan and NS._plan()
        if plan and plan.rate then
            GameTooltip:AddLine(("%s xp/hr planned"):format(NS.FormatNum(plan.rate)), 0.4, 1, 0.4)
            local s = plan.route and plan.route[1]
            if s and s.q then GameTooltip:AddLine("Next: " .. s.q.name, 1, 1, 1) end
        end
        GameTooltip:AddLine("Left-click: show/hide", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: replan", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag: move   /tq minimap: hide", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Place()
end

function NS.UpdateMinimap()
    if not NS.db or not Minimap then return end
    if NS.db.minimap == false then
        if button then button:Hide() end
        return
    end
    if not button then Build() end
    button:Show()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() C_Timer.After(0.2, NS.UpdateMinimap) end)
