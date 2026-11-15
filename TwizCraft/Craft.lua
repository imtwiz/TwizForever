-- TwizCraft crafting: click a step to craft it.
--   click        craft as many as your materials allow (up to the step's count)
--   shift-click  craft one
--   right-click  stop crafting
-- The game only crafts while that profession's window is open, so the
-- first click opens it if needed.
local ADDON, NS = ...

BINDING_HEADER_CRAFTROUTE = "TwizCraft"
BINDING_NAME_CRAFTROUTE_NEXT = "Craft next step"
BINDING_NAME_CRAFTROUTE_CRAFTALL = "Craft All: next batch of everything you can make"

local function ProfessionOpen(line)
    if not (C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo) then return false end
    local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
    if not ok or type(info) ~= "table" then return false end
    local id = NS.safe(info.professionID)
    if id ~= line and NS.safe(info.parentProfessionID) ~= line then return false end
    local frame = ProfessionsFrame or TradeSkillFrame
    return not frame or frame:IsShown()
end

local function OpenProfession(line, name)
    if C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
        local ok = pcall(C_TradeSkillUI.OpenTradeSkill, line)
        if ok then
            NS.Print(("opened %s - click again to craft."):format(name or "your profession"))
            return
        end
    end
    NS.Print(("open your %s window, then click again."):format(name or "profession"))
end

-- How many you can make from what's in your bags
local function CanMake(r)
    local n = math.huge
    for _, g in ipairs(r.reagents) do
        n = math.min(n, math.floor(NS.SlotBags(g) / math.max(1, g.qty)))
    end
    return n == math.huge and 0 or n
end

local function Missing(r)
    local out = {}
    for _, g in ipairs(r.reagents) do
        local have = NS.SlotBags(g)
        if have < g.qty then out[#out + 1] = ("%d %s"):format(g.qty - have, NS.ItemName(g.id)) end
    end
    return table.concat(out, ", ")
end

-- older clients: find the recipe's row in the list by name
local function LegacyIndex(name)
    if not (GetNumTradeSkills and GetTradeSkillInfo) then return end
    for i = 1, GetNumTradeSkills() do
        local n, kind = GetTradeSkillInfo(i)
        if n == name and kind ~= "header" then return i end
    end
end

local function DoCraft(id, r, count)
    if C_TradeSkillUI and C_TradeSkillUI.CraftRecipe then
        local ok, err = pcall(C_TradeSkillUI.CraftRecipe, id, count)
        if ok then return true end
        NS.Print("the game refused to craft: " .. tostring(err))
        return false
    end
    local idx = DoTradeSkill and LegacyIndex(r.name)
    if idx then DoTradeSkill(idx, count); return true end
    NS.Print("this client doesn't let addons start a craft - use the profession window's Create button.")
    return false
end

-- line: profession skill line; id: recipe id; r: recipe; want: how many the plan needs
function NS.CraftRecipeNow(line, id, r, want, profName, button)
    if button == "RightButton" then
        if C_TradeSkillUI and C_TradeSkillUI.StopRecipeRepeat then pcall(C_TradeSkillUI.StopRecipeRepeat) end
        if SpellStopCasting then pcall(SpellStopCasting) end
        NS.Print("stopped crafting.")
        return
    end
    if InCombatLockdown() then NS.Print("can't craft in combat."); return end
    if not r.learned then NS.Print(("learn %s from your trainer first."):format(r.name)); return end
    if not ProfessionOpen(line) then OpenProfession(line, profName); return end
    local can = CanMake(r)
    if can <= 0 then
        NS.Print(("missing materials for %s: %s"):format(r.name, Missing(r)))
        return
    end
    local count = IsShiftKeyDown() and 1 or math.max(1, math.min(can, want or can))
    if DoCraft(id, r, count) then
        NS.Print(("crafting %d %s%s"):format(count, r.name,
            (want and count < want) and (" (materials for %d of %d)"):format(count, want) or ""))
    end
end

function NS.CraftStep(st, plan, button)
    if not st or not plan then return end
    NS.CraftRecipeNow(plan.line, st.id, st.r, st.n, plan.name, button)
end

-- "make first" items (e.g. Light Leather from scraps, bolts of cloth)
function NS.CraftSub(sc, button)
    if not sc or not sc.id then return end
    local p = NS.Char().profs[sc.line]
    local r = p and p.recipes[sc.id]
    if not r then return end
    NS.CraftRecipeNow(sc.line, sc.id, r, sc.n, p.name, button)
end

-- keybind / "Craft next" button: first make-first item you can make, else step 1
function NS.CraftNext(button)
    local plan = NS.currentPlan
    if not plan then NS.Print("no plan yet."); return end
    for _, sc in ipairs(plan.subcrafts or {}) do
        local p = NS.Char().profs[sc.line]
        local r = p and p.recipes[sc.id]
        if r and CanMake(r) > 0 then return NS.CraftSub(sc, button) end
    end
    if plan.steps and plan.steps[1] then return NS.CraftStep(plan.steps[1], plan, button) end
    NS.Print("nothing to craft.")
end

------------------------------------------------------------------------
-- Craft All: everything you can make right now, in plan order - make-first
-- items, then each step. Each press crafts a whole batch of one recipe (as
-- many as your materials and the plan allow); the game needs a fresh click,
-- key or wheel notch to start the next recipe.
------------------------------------------------------------------------
function NS.CraftAllQueue()
    local plan = NS.currentPlan
    local q = {}
    if not plan then return q end
    for _, sc in ipairs(plan.subcrafts or {}) do
        local p = NS.Char().profs[sc.line]
        local r = p and p.recipes[sc.id]
        if r and r.learned and CanMake(r) > 0 then
            q[#q + 1] = { line = sc.line, id = sc.id, r = r, want = sc.n, prof = p.name }
        end
    end
    for _, st in ipairs(plan.steps or {}) do
        if st.r and st.r.learned and CanMake(st.r) > 0 then
            q[#q + 1] = { line = plan.line, id = st.id, r = st.r, want = st.n, prof = plan.name }
        end
    end
    -- the same recipe in several places (e.g. two skill ranges): one batch
    local merged, at = {}, {}
    for _, e in ipairs(q) do
        local m = at[e.id]
        if m then m.want = (m.want or 0) + (e.want or 0)
        else at[e.id] = e; merged[#merged + 1] = e end
    end
    return merged
end

local function Busy()
    if UnitCastingInfo and UnitCastingInfo("player") then return true end
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeRepeatCount then
        local ok, n = pcall(C_TradeSkillUI.GetRecipeRepeatCount)
        if ok and (n or 0) > 0 then return true end
    end
    return false
end

local lastBusyMsg = 0
local current
function NS.CraftAll(button)
    if button == "RightButton" then
        current = nil
        return NS.CraftRecipeNow(nil, nil, nil, nil, nil, "RightButton")
    end
    if Busy() then
        if GetTime() - lastBusyMsg > 3 then
            lastBusyMsg = GetTime()
            NS.Print("still crafting - Craft All picks up the next recipe when this batch is done.")
        end
        return
    end
    if NS.PlanNow then NS.PlanNow() end
    local q = NS.CraftAllQueue()
    local first = q[1]
    if not first then
        NS.Print("nothing you can craft with what's in your bags right now.")
        NS.UpdateCraftWheel()
        return
    end
    current = first.r.name
    NS.CraftRecipeNow(first.line, first.id, first.r, first.want, first.prof, button)
    if #q > 1 then
        NS.Print(("%d more recipe%s after this batch - press Craft All again or spin your mouse wheel."):format(
            #q - 1, #q == 2 and "" or "s"))
    end
    NS.UpdateCraftWheel()
end

-- While the profession window is open and something is craftable, the mouse
-- wheel (outside scrolling lists) presses Craft All. Released when done.
local wheelOwner = CreateFrame("Frame")
local wheelBound = false
function NS.UpdateCraftWheel()
    local plan = NS.currentPlan
    local want = NS.db and NS.db.wheelCraft ~= false and plan and ProfessionOpen(plan.line)
        and #NS.CraftAllQueue() > 0 and true or false
    if want == wheelBound or InCombatLockdown() then return end
    if want then
        SetOverrideBinding(wheelOwner, true, "MOUSEWHEELUP", "CRAFTROUTE_CRAFTALL")
        SetOverrideBinding(wheelOwner, true, "MOUSEWHEELDOWN", "CRAFTROUTE_CRAFTALL")
    else
        ClearOverrideBindings(wheelOwner)
    end
    wheelBound = want
end

-- tell you when a batch finishes and what's next
local ev = CreateFrame("Frame")
ev:RegisterEvent("TRADE_SKILL_SHOW")
ev:RegisterEvent("TRADE_SKILL_CLOSE")
ev:RegisterEvent("UNIT_SPELLCAST_STOP")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_SPELLCAST_STOP" then
        if unit ~= "player" or not current then return end
        C_Timer.After(0.4, function()
            if Busy() or not current then return end
            current = nil
            local q = NS.CraftAllQueue()
            if q[1] then
                NS.Print(("batch done - next: %s (%d recipe%s left). Press Craft All or spin the wheel."):format(
                    q[1].r.name, #q, #q == 1 and "" or "s"))
            else
                NS.Print("Craft All finished - nothing left you can make right now.")
            end
            NS.UpdateCraftWheel()
            if NS.RefreshUI then NS.RefreshUI() end
        end)
        return
    end
    C_Timer.After(0.3, NS.UpdateCraftWheel)
end)
