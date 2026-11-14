-- TwizQuest window: the ordered steps, XP/hour, and click-to-waypoint.
local ADDON, NS = ...

local ROWS, DEFAULT_ROWS, ROW_H = 40, 16, 18
local plan
local frame, rows = nil, {}
local wayUID

local KIND_TEXT = {
    pickup = "|cffffd100Pick up|r",
    turnin = "|cff00ff66Turn in|r",
}

local function StepText(s)
    local q = s.q
    if s.kind == "service" then
        return ("|cffff9933%s|r at %s |cff999999- %s|r"):format(s.repair and "Sell & repair" or "Sell junk",
            s.who or "a vendor", s.why or "")
    end
    if s.kind == "bank" then
        return ("  |cff40c0ffBank:|r get %d %s |cff999999- %s|r"):format(s.need or 0, s.name or "items", q.name)
    elseif s.kind == "useitem" then
        return ("%s %s |cff999999- use your %s|r"):format(KIND_TEXT.pickup, q.name, s.name or "item")
    elseif s.kind == "bankstart" then
        return ("%s %s |cff999999- get %s from the bank, then use it|r"):format(KIND_TEXT.pickup, q.name, s.name or "the item")
    end
    if s.role == 1 then
        return ("%s %s%s"):format(KIND_TEXT.pickup, q.name, s.who and (" |cff999999- " .. s.who .. "|r") or "")
    elseif s.role == 3 then
        return ("%s %s%s"):format(KIND_TEXT.turnin, q.name, s.who and (" |cff999999- " .. s.who .. "|r") or "")
    end
    local what
    if s.kind == "monster" or s.kind == "killcredit" then
        what = ("Kill %d %s"):format(s.need or 0, s.name or s.text or "targets")
    elseif s.kind == "item" then
        what = ("Get %d %s%s"):format(s.need or 0, s.name or s.text or "items",
            s.dropper and (" (~" .. (s.kills or s.need) .. " " .. s.dropper .. ")") or "")
    elseif s.kind == "loot" or s.kind == "object" then
        what = ("Collect %d %s"):format(s.need or 0, s.name or s.text or "objects")
    elseif s.kind == "buy" then
        what = ("Buy %s from %s"):format(s.name or "item", s.vendor or "vendor")
    else
        what = s.text or "Objective"
    end
    if s.elite then what = what .. " |cffff5555(elite)|r" end
    return ("  %s |cff999999- %s|r"):format(what, q.name)
end

local function SetWaypoint(s, silent)
    if not s or not s.map then return end
    local title = (s.role == 1 and "Pick up: " or s.role == 3 and "Turn in: " or "") .. s.q.name
    if TomTom and TomTom.AddWaypoint then
        if wayUID and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, wayUID) end
        local ok, uid = pcall(TomTom.AddWaypoint, TomTom, s.map, s.mx / 100, s.my / 100,
            { title = title, from = "TwizQuest", persistent = false, crazy = true })
        if ok then wayUID = uid end
    elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint then
        pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(s.map, s.mx / 100, s.my / 100))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
    end
    if not silent then NS.Print("waypoint set: " .. title) end
end

-- rows that fit: your chosen height, or the default when you haven't resized
local function RowsFit()
    if NS.db.sized then return math.max(1, math.min(ROWS, math.floor((frame:GetHeight() - 66) / ROW_H))) end
    return DEFAULT_ROWS
end

-- widths follow the window
local function Layout()
    if not frame then return end
    local w = frame:GetWidth()
    for _, row in ipairs(rows) do
        row:SetWidth(w - 20)
        row.text:SetWidth(math.max(80, w - 20 - 24 - 100))
    end
end

local function Refresh()
    if not frame then return end
    if not plan then
        frame.summary:SetText(NS.IsPlanning() and "Planning..." or (frame.status or "No plan yet. Click Plan."))
        for i = 1, ROWS do rows[i]:Hide() end
        if not NS.db.sized then frame:SetHeight(80) end
        return
    end
    local need = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
    local toLevel = (plan.rate > 0) and (need / plan.rate * 3600) or nil
    local age = GetTime() - (plan.at or GetTime())
    frame.summary:SetText(("|cff66ff66%s xp/hr|r   %s xp in %s   %s%s"):format(
        NS.FormatNum(plan.rate), NS.FormatNum(plan.xp), NS.FormatTime(plan.time),
        toLevel and ("|cff999999level in ~" .. NS.FormatTime(toLevel) .. "|r") or "",
        NS.IsPlanning() and "  |cffffff00updating...|r" or
            ("  |cff777777" .. (age < 5 and "just now" or NS.FormatTime(age) .. " ago") .. "|r"))
        .. (((plan.skipped or 0) > 0) and ("  |cffff8040(%d skipped, /qr error)|r"):format(plan.skipped) or "")
        .. (((plan.rested or 0) > 0) and ("  |cff6699ffrested %s|r"):format(NS.FormatNum(plan.rested)) or "")
        .. ((#(plan.drop or {}) > 0) and ("  |cffffd100%d to drop (/qr cleanup)|r"):format(#plan.drop) or ""))
    local shown, fit = 0, RowsFit()
    for i = 1, ROWS do
        local s = (i <= fit) and plan.route[i] or nil
        local row = rows[i]
        if s then
            row.step = s
            row.num:SetText(i .. ".")
            row.text:SetText(StepText(s))
            local gain = (s.kxp or 0) + ((s.role == 3) and s.q.xp or 0)
            row.right:SetText(("%s%s"):format(
                gain > 0 and ("+" .. NS.FormatNum(gain) .. " ") or "",
                "|cff999999" .. NS.FormatTime(s.eta) .. "|r"))
            row:Show(); shown = i
        else
            row:Hide()
        end
    end
    if #plan.route == 0 then
        frame.summary:SetText("Nothing worth doing nearby. Try /qr range 5000 or /qr above 4.")
    end
    if not NS.db.sized then frame:SetHeight(58 + shown * ROW_H) end
end

local function Build()
    frame = CreateFrame("Frame", "TwizQuestFrame", UIParent, "BackdropTemplate")
    frame:SetSize(470, 80)
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 60)
    frame:SetMovable(true); frame:EnableMouse(true); frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        NS.db.pos = { p, rp, x, y }
    end)
    if frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        frame:SetBackdropColor(0, 0, 0, 0.8)
    end
    if NS.db.pos then
        frame:ClearAllPoints()
        frame:SetPoint(NS.db.pos[1], UIParent, NS.db.pos[2], NS.db.pos[3], NS.db.pos[4])
    end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("TwizQuest")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() frame:Hide(); NS.db.shown = false end)

    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btn:SetSize(56, 18); btn:SetPoint("TOPRIGHT", -28, -6)
    btn:SetText("Plan")
    btn:SetScript("OnClick", function() NS.Replan() end)

    frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.summary:SetPoint("TOPLEFT", 10, -28)
    frame.summary:SetPoint("RIGHT", -10, 0)
    frame.summary:SetJustifyH("LEFT")

    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(450, ROW_H)
        row:SetPoint("TOPLEFT", 10, -46 - (i - 1) * ROW_H)
        row:RegisterForClicks("AnyUp")
        row.num = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.num:SetPoint("LEFT"); row.num:SetWidth(20); row.num:SetJustifyH("RIGHT")
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 24, 0); row.text:SetWidth(330); row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.right:SetPoint("RIGHT"); row.right:SetJustifyH("RIGHT")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
        row:SetScript("OnClick", function(self) SetWaypoint(self.step) end)
        row:SetScript("OnEnter", function(self)
            local s = self.step
            if not s then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(s.q.name, 1, 0.82, 0)
            local plain = StepText(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            GameTooltip:AddLine(plain, 1, 1, 1, true)
            GameTooltip:AddDoubleLine("Travel", ("%d yd, %s"):format(s.dist or 0, NS.FormatTime(s.travel or 0)), 0.7, 0.7, 0.7, 1, 1, 1)
            GameTooltip:AddDoubleLine("Doing it", NS.FormatTime(s.work or 0), 0.7, 0.7, 0.7, 1, 1, 1)
            if (s.kxp or 0) > 0 then GameTooltip:AddDoubleLine("Kill XP", NS.FormatNum(s.kxp), 0.7, 0.7, 0.7, 1, 1, 1) end
            if s.role == 3 then GameTooltip:AddDoubleLine("Quest XP", NS.FormatNum(s.q.xp), 0.7, 0.7, 0.7, 1, 1, 1) end
            GameTooltip:AddLine("Click for a waypoint", 0.5, 0.8, 1)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        rows[i] = row
    end
    local resizing
    NS.resetSize = NS.MakeResizable(frame, NS.db, {
        minW = 320, minH = 100, maxW = 1400, maxH = 1000, defaultW = 470, defaultH = 80, savePos = true,
        onResize = function()
            if resizing then return end
            resizing = true; Layout(); Refresh(); resizing = false
        end })
    Layout()
    if not NS.db.shown then frame:Hide() end
end

------------------------------------------------------------------------
-- Target key: targets the mob or NPC for step 1 (a secure button, so it
-- works from a key binding; updated out of combat whenever the plan changes)
------------------------------------------------------------------------
local targetButton, targetDirty
local function StepTargetName(s)
    if not s then return nil end
    if s.kind == "monster" or s.kind == "killcredit" then return s.name end
    if s.kind == "item" then return s.dropper end
    if s.role == 1 or s.role == 3 or s.kind == "service" then return s.who end
end

function NS.UpdateTargetButton()
    if not targetButton then return end
    if InCombatLockdown() then targetDirty = true; return end
    targetDirty = false
    local name = plan and plan.route[1] and StepTargetName(plan.route[1])
    targetButton:SetAttribute("macrotext", name and ("/targetexact " .. name) or "")
    targetButton.name = name
end

local function MakeTargetButton()
    targetButton = CreateFrame("Button", "TwizQuestTargetButton", UIParent, "SecureActionButtonTemplate")
    targetButton:SetSize(1, 1); targetButton:SetAlpha(0)
    targetButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
    targetButton:RegisterForClicks("AnyUp", "AnyDown")
    targetButton:SetAttribute("type", "macro")
    targetButton:SetAttribute("macrotext", "")
end

function NS.OnPlan(result, why)
    if result then
        plan = result
        NS.UpdateTargetButton()
        if NS.db.autoWay and result.route[1] then SetWaypoint(result.route[1], true) end
    elseif frame then
        frame.status = "Can't plan yet: " .. tostring(why or "unknown") .. "  (/qr error)"
    end
    Refresh()
end

------------------------------------------------------------------------
-- Keeping the plan up to date by itself
------------------------------------------------------------------------
local dirty = true          -- something changed: search all quests again
function NS.MarkDirty() dirty = true end
function NS._plan() return plan end
local lastFull = -999
local wantFull = false      -- a manual "Plan" asked while busy

local function Moved(dist)
    if not plan then return true end
    local x, y, inst = NS.PlayerPos()
    return x and (inst ~= plan.inst or NS.Dist(x, y, plan.x, plan.y) > dist)
end

local function Tick()
    if not NS.db or not NS.Bridge() or NS.IsPlanning() then return end
    if wantFull then
        wantFull, dirty, lastFull = false, false, GetTime()
        NS.Plan(true); Refresh(); return
    end
    if not NS.db.auto then Refresh(); return end
    if InCombatLockdown() then return end            -- catch up right after the fight
    local t = GetTime()
    if (dirty and t - lastFull >= 6) or t - lastFull >= 120 or Moved(400) then
        dirty, lastFull = false, t
        NS.Plan(true)
    elseif not dirty and Moved(60) then
        NS.Plan(false)
    end
    Refresh()
end

-- Kept for the Plan button and slash commands: re-plan as soon as possible.
function NS.Replan()
    wantFull = true
    Tick()
end

-- Drop a finished step right away, before the next plan comes in.
local function Done(questID, role)
    if not plan or not questID then return end
    for i = #plan.route, 1, -1 do
        local s = plan.route[i]
        if s.q.id == questID and s.role == role then table.remove(plan.route, i) end
    end
    if NS.db.autoWay and plan.route[1] then SetWaypoint(plan.route[1], true) end
    NS.UpdateTargetButton()
    Refresh()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
    "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "MERCHANT_CLOSED", "GROUP_ROSTER_UPDATE",
    "UPDATE_INVENTORY_DURABILITY", "PLAYER_UPDATE_RESTING", "BAG_UPDATE_DELAYED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "PLAYER_LOGIN" then
        Build()
        MakeTargetButton()
        C_Timer.NewTicker(3, Tick)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if targetDirty then NS.UpdateTargetButton() end
        return
    end
    if event == "MERCHANT_CLOSED" and plan then
        -- sold and repaired: the service stop is done
        for i = #plan.route, 1, -1 do if plan.route[i].kind == "service" then table.remove(plan.route, i) end end
        Refresh()
    end
    if event == "UPDATE_INVENTORY_DURABILITY" or event == "PLAYER_UPDATE_RESTING" or event == "BAG_UPDATE_DELAYED" then
        -- only matters if it changes whether a service stop is needed / rested XP
        local need = NS.ServiceNeed and select(2, NS.ServiceNeed()) or nil
        if (need ~= nil) == (plan and plan.service ~= nil) and event ~= "PLAYER_UPDATE_RESTING" then return end
    end
    dirty = true
    if event == "QUEST_ACCEPTED" then
        Done(a2 or a1, 1)          -- older clients pass (logIndex, questID)
    elseif event == "QUEST_TURNED_IN" then
        Done(a1, 3)
    end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local function Help()
    NS.Print("commands:")
    print("  /qr              - show or hide the route window")
    print("  /qr plan         - re-plan now (it also updates by itself)")
    print("  /qr auto         - automatic updates (now " .. (NS.db.auto and "on" or "off") .. ")")
    print("  /qr next         - waypoint to the first step")
    print("  /qr time 60      - minutes of play to plan (now " .. NS.db.horizon .. ")")
    print("  /qr above 3      - max levels above you a quest can be (now " .. NS.db.maxAbove .. ")")
    print("  /qr range 3000   - max yards to a quest giver (now " .. NS.db.maxDist .. ")")
    print("  /qr elites       - include quests with elite kills (now " .. (NS.db.elites and "on" or "off") .. ")")
    print("  /qr way          - auto-waypoint step 1 (now " .. (NS.db.autoWay and "on" or "off") .. ")")
    print("  /qr learned      - what it has learned about how you play")
    print("  /qr size         - reset the window size (drag the bottom-right corner to resize)")
    print("  /qr relearn      - forget learned speeds and rates")
    print("  /qr cleanup      - quests in your log that aren't worth their slot; /qr abandon drops them")
    print("  /qr service      - sell & repair stop when bags are nearly full / gear is breaking (now " .. (NS.db.service and "on" or "off") .. ")")
    print("  Key bindings (Options > Keybindings > AddOns > TwizQuest): target step 1's mob/NPC, waypoint to step 1")
end

SLASH_QUESTROUTE1 = "/qr"
SLASH_QUESTROUTE2 = "/twizquest"
SLASH_QUESTROUTE3 = "/questroute"
SlashCmdList.QUESTROUTE = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "cleanup" or cmd == "abandon" then
        local drop = plan and plan.drop or {}
        if #drop == 0 then NS.Print("every quest in your log is worth keeping right now."); return end
        if cmd == "cleanup" then
            NS.Print(("%d quest(s) aren't worth their log slot:"):format(#drop))
            for _, d in ipairs(drop) do print(("  %s - %s"):format(d.name, d.why)) end
            print("  /qr abandon drops them all (asks first).")
        else
            StaticPopupDialogs.TWIZQUEST_ABANDON = StaticPopupDialogs.TWIZQUEST_ABANDON or {
                text = "Abandon %d quest(s) that aren't worth it?\n(See chat for the list.)",
                button1 = YES or "Yes", button2 = NO or "No", timeout = 0, hideOnEscape = true, preferredIndex = 3,
                OnAccept = function(_, list)
                    for _, d in ipairs(list) do
                        pcall(C_QuestLog.SetSelectedQuest, d.id)
                        pcall(C_QuestLog.SetAbandonQuest)
                        pcall(C_QuestLog.AbandonQuest)
                    end
                    NS.Print(("abandoned %d quest(s)."):format(#list))
                    NS.Replan()
                end,
            }
            for _, d in ipairs(drop) do print(("  %s - %s"):format(d.name, d.why)) end
            StaticPopup_Show("TWIZQUEST_ABANDON", #drop, nil, drop)
        end
        return
    elseif cmd == "service" then
        NS.db.service = not NS.db.service
        NS.Print("sell & repair stops " .. (NS.db.service and "on" or "off"))
        NS.Replan()
        return
    end
    cmd = (cmd or ""):lower()
    local n = tonumber(rest)
    if cmd == "" then
        if frame:IsShown() then frame:Hide(); NS.db.shown = false
        else frame:Show(); NS.db.shown = true; Refresh() end
    elseif cmd == "plan" then NS.Replan()
    elseif cmd == "size" or cmd == "scale" then NS.resetSize(); NS.Print("window size reset")
    elseif cmd == "next" then
        if plan and plan.route[1] then SetWaypoint(plan.route[1]) else NS.Print("no plan yet.") end
    elseif cmd == "time" and n then NS.db.horizon = math.max(10, math.min(n, 240)); NS.Replan()
    elseif cmd == "above" and n then NS.db.maxAbove = math.max(0, math.min(n, 10)); NS.Replan()
    elseif cmd == "range" and n then NS.db.maxDist = math.max(300, n); NS.Replan()
    elseif cmd == "elites" then
        NS.db.elites = not NS.db.elites
        NS.Print("elite quests " .. (NS.db.elites and "included" or "skipped")); NS.Replan()
    elseif cmd == "auto" then
        NS.db.auto = not NS.db.auto
        NS.Print("automatic updates " .. (NS.db.auto and "on" or "off"))
    elseif cmd == "way" then
        NS.db.autoWay = not NS.db.autoWay
        NS.Print("auto-waypoint " .. (NS.db.autoWay and "on" or "off"))
    elseif cmd == "learned" then
        local L = NS.db.learn
        NS.Print("learned so far:")
        print(("  on foot %.1f yd/s, mounted %s"):format(L.runSpeed,
            L.mountSeen >= 10 and ("%.1f yd/s"):format(L.mountSpeed) or "not seen yet"))
        print(("  %.0fs fighting + %.0fs resting per kill (%d kills watched)"):format(L.secPerKill, L.restPerKill, L.kills))
        print(("  kill XP x%.2f of formula, quest XP x%.2f of database (%d turn-ins)"):format(
            L.killXPRatio, L.questXPRatio, L.quests))
        local at = NS.BankKnown()
        print(at and ("  bank contents remembered " .. NS.FormatTime(time() - at) .. " ago")
            or "  bank not seen yet - open your bank once so quest items there are counted")
    elseif cmd == "error" then
        local e = NS.db.lastError
        if not e then NS.Print("no errors recorded."); return end
        NS.Print("last problem: " .. e.msg)
        for line in (e.stack or ""):gmatch("[^\n]+") do print("  " .. line) end
    elseif cmd == "relearn" then
        NS.db.learn = {}
        for k, v in pairs(NS.DEFAULTS.learn) do NS.db.learn[k] = v end
        NS.Print("forgot everything learned; back to defaults.")
    else
        Help()
    end
end
