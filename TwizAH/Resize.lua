-- Resize grip: drag the bottom-right corner to change the window's width and
-- height (text stays the same size; you get more room, rows and columns).
-- Right-click the grip to go back to the default size.
local ADDON, NS = ...

-- opts: minW, minH, maxW, maxH, defaultW, defaultH, savePos, onResize
-- store keeps winW / winH / sized (and pos if savePos)
function NS.MakeResizable(frame, store, opts)
    -- an earlier version scaled windows instead; undo that
    store.scale = nil
    frame:SetScale(1)

    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(opts.minW, opts.minH, opts.maxW, opts.maxH)
    else
        if frame.SetMinResize then frame:SetMinResize(opts.minW, opts.minH) end
        if frame.SetMaxResize then frame:SetMaxResize(opts.maxW, opts.maxH) end
    end
    if store.sized and store.winW and store.winH then
        frame:SetSize(store.winW, store.winH)
    end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    local function SavePos()
        if opts.savePos then
            local p, _, rp, x, y = frame:GetPoint()
            store.pos = { p, rp, x, y }
        end
    end

    local function Reset()
        store.sized, store.winW, store.winH = nil, nil, nil
        frame:SetSize(opts.defaultW, opts.defaultH)
        if opts.onResize then opts.onResize() end
    end

    grip:SetScript("OnMouseDown", function(_, button)
        if button == "RightButton" then Reset(); return end
        -- pin the top-left corner so only the bottom-right edge moves
        local l, t = frame:GetLeft(), frame:GetTop()
        if l and t then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
        end
        store.sized = true
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then return end
        frame:StopMovingOrSizing()
        store.winW, store.winH = frame:GetWidth(), frame:GetHeight()
        SavePos()
        if opts.onResize then opts.onResize() end
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Drag to resize")
        GameTooltip:AddLine("Right-click to reset", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame:HookScript("OnSizeChanged", function()
        if opts.onResize then opts.onResize() end
    end)
    return Reset
end
