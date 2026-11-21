-- TwizCraft capture: reads your recipes whenever a profession window is open,
-- adds AtlasLoot's skill colors, keeps your current skill, and learns your
-- real skill-up odds from each craft.
local ADDON, NS = ...

local function AL()
    return AtlasLoot and AtlasLoot.Data and AtlasLoot.Data.Profession
end

-- AtlasLoot: [spellID] = { createdItem, profession, orange, yellow, gray, {reagents}, {counts}, made }
local function Thresholds(recipeID, outputID)
    local P = AL()
    if not P then return nil end
    local d = P.GetProfessionData(recipeID)
    if not d and outputID and P.GetCraftSpellForCreatedItem then
        local ok, sid = pcall(P.GetCraftSpellForCreatedItem, outputID)
        if ok and sid then d = P.GetProfessionData(sid) end
    end
    if not d or not d[4] or not d[5] then return nil end
    local yellow, gray = d[4], d[5]
    local orange = (d[3] and d[3] > 0) and d[3] or yellow
    return { orange = orange, yellow = yellow, green = math.floor((yellow + gray) / 2), gray = gray,
             alReagents = d[6], alCounts = d[7], alMade = d[8] }
end

-- Guess thresholds from today's color when AtlasLoot doesn't know the recipe
local function Guess(diff, skill)
    if diff == 0 then return { orange = skill - 5, yellow = skill + 5, green = skill + 15, gray = skill + 25, guess = true } end
    if diff == 1 then return { orange = skill - 15, yellow = skill - 5, green = skill + 5, gray = skill + 15, guess = true } end
    if diff == 2 then return { orange = skill - 25, yellow = skill - 15, green = skill - 5, gray = skill + 5, guess = true } end
    return { orange = skill - 40, yellow = skill - 30, green = skill - 20, gray = skill - 10, guess = true }
end

-- every profession (gathering and secondary too) by name -> skill line id
local LINES = {
    Alchemy = 171, Blacksmithing = 164, Enchanting = 333, Engineering = 202, Herbalism = 182,
    Leatherworking = 165, Mining = 186, Skinning = 393, Tailoring = 197, Jewelcrafting = 755,
    Inscription = 773, Cooking = 185, ["First Aid"] = 129, Fishing = 356, Archaeology = 794,
}
NS.PROFESSION_LINES = LINES

-- Your professions and skill, even with the window closed: every one you
-- have, not just the ones whose window you've opened
function NS.Professions()
    local out, seen = {}, {}
    local function add(name, icon, rank, maxRank, line)
        if not name or name == "" then return end
        line = line or LINES[name]
        local key = line or name
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = { name = name, icon = icon, skill = rank or 0, max = maxRank or 0, line = line }
    end
    if GetProfessions and GetProfessionInfo then
        local list = { GetProfessions() }
        for i = 1, 5 do
            local idx = list[i]
            if idx then
                local ok, name, icon, rank, maxRank, _, _, skillLine = pcall(GetProfessionInfo, idx)
                if ok then add(name, icon, rank, maxRank, skillLine) end
            end
        end
    end
    -- Classic-style skill list: catches anything GetProfessions misses
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if not isHeader and name and LINES[name] then add(name, nil, rank, maxRank, LINES[name]) end
        end
    end
    return out
end

function NS.SkillFor(line, name)
    for _, p in ipairs(NS.Professions()) do
        if (line and p.line == line) or p.name == name then return p.skill, p.max end
    end
end

local Capture
Capture = function()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo) then return end
    if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then return end
    if C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild() then return end
    local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
    if not ok or type(info) ~= "table" then return end
    local line = NS.safe(info.professionID)
    local name = NS.safe(info.professionName) or NS.safe(info.parentProfessionName)
    if not line or not name then return end
    local skill = NS.safe(info.skillLevel) or NS.SkillFor(line, name) or 0

    local okIds, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not okIds or type(ids) ~= "table" or #ids == 0 then return end

    local recipes, n = {}, 0
    for _, raw in ipairs(ids) do
        local id = NS.safe(raw)
        local okR, ri = pcall(C_TradeSkillUI.GetRecipeInfo, id)
        local okS, sc = pcall(C_TradeSkillUI.GetRecipeSchematic, id, false)
        if id and okR and ri and okS and sc then
            local out = NS.safe(sc.outputItemID)
            local reagents = {}
            for _, slot in ipairs(sc.reagentSlotSchematics or {}) do
                if NS.safe(slot.required) ~= false and slot.reagents and slot.reagents[1] then
                    local alts = {}
                    for _, rg in ipairs(slot.reagents) do
                        local aid = NS.safe(rg.itemID)
                        if type(aid) == "number" then alts[#alts + 1] = aid end
                    end
                    local qty = NS.safe(slot.quantityRequired) or 1
                    if alts[1] then reagents[#reagents + 1] = { id = alts[1], qty = qty, alts = #alts > 1 and alts or nil } end
                end
            end
            local learned = NS.safe(ri.learned) and true or false
            local th = Thresholds(id, out)
            if not th and learned then th = Guess(NS.safe(ri.relativeDifficulty), skill) end
            if th and #reagents > 0 then
                local made = ((NS.safe(sc.quantityMin) or 1) + (NS.safe(sc.quantityMax) or NS.safe(sc.quantityMin) or 1)) / 2
                local recipeItem
                local R = AtlasLoot and AtlasLoot.Data and AtlasLoot.Data.Recipe
                if R and R.GetRecipeForSpell then
                    local okI, ri2 = pcall(R.GetRecipeForSpell, id)
                    if okI and ri2 then recipeItem = type(ri2) == "table" and ri2[1] or ri2 end
                end
                local cast = 3
                if C_Spell and C_Spell.GetSpellInfo then
                    local okC, si = pcall(C_Spell.GetSpellInfo, id)
                    if okC and si and si.castTime and si.castTime > 0 then cast = si.castTime / 1000 end
                end
                recipes[id] = {
                    name = NS.safe(ri.name) or ("Recipe " .. id), out = out, made = made,
                    reagents = reagents, learned = learned, recipeItem = recipeItem,
                    orange = th.orange, yellow = th.yellow, green = th.green, gray = th.gray,
                    guess = th.guess, cast = cast,
                }
                n = n + 1
            end
        end
    end
    if n == 0 then return end
    local c = NS.Char()
    local before = c.profs[line] and c.profs[line].count or 0
    c.profs[line] = { name = name, line = line, recipes = recipes, count = n, at = time(), skill = skill }
    if n ~= before then NS.Print(("remembered %d %s recipes."):format(n, name)) end
    NS.current = line
    if NS.Replan then NS.Replan() end
    if NS.PartyRecipesChanged then NS.PartyRecipesChanged() end
    return n
end
NS.Capture = function() local ok, n = pcall(Capture); return ok and n end

------------------------------------------------------------------------
-- Learning your real skill-up odds
------------------------------------------------------------------------
local pending
local function OnCast(spellID)
    local c = NS.db and NS.Char()
    if not c then return end
    for line, p in pairs(c.profs) do
        local r = p.recipes[spellID]
        if r then
            local skill = NS.SkillFor(line, p.name)
            if not skill then return end
            local zone = NS.Color(r, skill)
            if zone == "yellow" or zone == "green" then
                pending = { line = line, name = p.name, skill = skill, zone = zone, p = NS.Chance(r, skill) }
                C_Timer.After(1.5, function()
                    local pd = pending
                    pending = nil
                    if not pd then return end
                    local now = NS.SkillFor(pd.line, pd.name)
                    if now then NS.RecordOdds(pd.zone, pd.p, now > pd.skill) end
                end)
            end
            return
        end
    end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "NEW_RECIPE_LEARNED", "UNIT_SPELLCAST_SUCCEEDED", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL",
    "BAG_UPDATE_DELAYED" }) do
    pcall(f.RegisterEvent, f, e)
end
local queued
f:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if not NS.db then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if a1 == "player" and type(a3) == "number" then OnCast(a3) end
        return
    end
    if event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" or event == "BAG_UPDATE_DELAYED" then
        if NS.Replan then NS.Replan() end
        -- a skill-up or a newly learned profession: tell the party
        if event ~= "BAG_UPDATE_DELAYED" and NS.PartyRecipesChanged then NS.PartyRecipesChanged() end
        return
    end
    if queued then return end
    queued = true
    C_Timer.After(0.5, function() queued = false; pcall(Capture) end)
end)

------------------------------------------------------------------------
-- Read every crafting profession by itself (Alchemy, Blacksmithing, ...), so
-- friends see all your recipes without you opening each window. Runs once a
-- session, out of combat, only for professions whose recipes are missing or
-- whose skill moved since they were read. The window opens and closes quickly.
------------------------------------------------------------------------
local GATHERING = { Herbalism = true, Skinning = true, Mining = true, Fishing = true, Archaeology = true }
local reading, readQueue = false, nil

local function WindowOpen()
    local frame = ProfessionsFrame or TradeSkillFrame
    return frame and frame:IsShown()
end

local function CloseProfession()
    if C_TradeSkillUI and C_TradeSkillUI.CloseTradeSkill then pcall(C_TradeSkillUI.CloseTradeSkill) end
    local frame = ProfessionsFrame or TradeSkillFrame
    if frame and frame:IsShown() and HideUIPanel then pcall(HideUIPanel, frame) end
end

local function ReadNext()
    if not readQueue or #readQueue == 0 then
        if reading then
            reading = false
            if NS.PartyRecipesChanged then NS.PartyRecipesChanged() end
        end
        return
    end
    if InCombatLockdown and InCombatLockdown() then C_Timer.After(5, ReadNext); return end
    if WindowOpen() then C_Timer.After(5, ReadNext); return end -- you're using a profession: wait
    local p = table.remove(readQueue, 1)
    if not (C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill) or not pcall(C_TradeSkillUI.OpenTradeSkill, p.line) then
        return C_Timer.After(0.2, ReadNext)
    end
    local tries = 0
    local function Try()
        tries = tries + 1
        local n = NS.Capture and NS.Capture()
        if (n and n > 0) or tries >= 10 then
            CloseProfession()
            -- the recipe list didn't load in time: try that profession again later (up to 3 times)
            if not (n and n > 0) then
                p.attempts = (p.attempts or 0) + 1
                if p.attempts < 3 then
                    C_Timer.After(15, function()
                        readQueue = readQueue or {}
                        readQueue[#readQueue + 1] = p
                        if not reading then reading = true; ReadNext() end
                    end)
                end
            end
            C_Timer.After(0.5, ReadNext)
        else
            C_Timer.After(0.5, Try)
        end
    end
    C_Timer.After(0.6, Try)
end

-- onlyLine: read just that profession (a friend asked for it)
function NS.ReadAllProfessions(force, onlyLine)
    if reading then
        if onlyLine then C_Timer.After(10, function() NS.ReadAllProfessions(force, onlyLine) end) end
        return
    end
    local c = NS.Char()
    readQueue = {}
    for _, p in ipairs(NS.Professions()) do
        if p.line and not GATHERING[p.name] and (not onlyLine or p.line == onlyLine) then
            local have = c.profs[p.line]
            if force or not have or (have.count or 0) == 0 or (have.skill and have.skill ~= p.skill) then
                readQueue[#readQueue + 1] = p
            end
        end
    end
    if #readQueue == 0 then return end
    reading = true
    ReadNext()
end

local readEv = CreateFrame("Frame")
readEv:RegisterEvent("PLAYER_ENTERING_WORLD")
readEv:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    C_Timer.After(12, function()
        if NS.db and NS.db.autoRead ~= false then NS.ReadAllProfessions() end
    end)
end)
