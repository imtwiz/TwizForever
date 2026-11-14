-- CraftRoute crafting: click a step to craft it.
--   click        craft as many as your materials allow (up to the step's count)
--   shift-click  craft one
--   right-click  stop crafting
-- The game only crafts while that profession's window is open, so the
-- first click opens it if needed.
local ADDON, NS = ...

BINDING_HEADER_CRAFTROUTE = "CraftRoute"
BINDING_NAME_CRAFTROUTE_NEXT = "Craft next step"

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
