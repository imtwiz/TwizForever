-- CraftRoute planner: for every skill point from your current skill to the
-- cap, pick the recipe with the lowest expected cost per point, then group
-- the run into steps and build the shopping list.
local ADDON, NS = ...

local FARM_MIN = 500 -- 5s: rough value for something you'd have to gather yourself

------------------------------------------------------------------------
-- Reagent costs (cheapest of vendor, AH, or crafting it yourself)
------------------------------------------------------------------------
local memo, producers

local function BuildProducers()
    producers = {}
    for line, p in pairs(NS.Char().profs) do
        for id, r in pairs(p.recipes) do
            if r.learned and r.out then
                producers[r.out] = producers[r.out] or {}
                table.insert(producers[r.out], { id = id, r = r, line = line })
            end
        end
    end
end

local UnitCost
local function RecipeMats(r, depth)
    local total, farm = 0, false
    for _, g in ipairs(r.reagents) do
        local c, src = UnitCost(g.id, depth + 1)
        total = total + c * g.qty
        if src == "farm" then farm = true end
    end
    return total, farm
end

-- returns cost per unit, source ("vendor" | "AH" | "craft" | "farm"), extra
UnitCost = function(id, depth)
    depth = depth or 0
    local canCraft = depth < 2
    local key = canCraft and id or -id
    local m = memo[key]
    if m then return m.cost, m.src, m.extra end
    local best, src, extra
    local v, npc, zone, est = NS.VendorBuy(id)
    if v then best, src, extra = v, "vendor", { npc = npc, zone = zone, est = est } end
    local a = NS.AHPrice(id)
    if a and (not best or a < best) then best, src, extra = a, "AH", nil end
    if canCraft then
        for _, pr in ipairs(producers[id] or {}) do
            local mats, farm = RecipeMats(pr.r, depth)
            local per = mats / math.max(1, pr.r.made or 1)
            if not farm and (not best or per < best) then best, src, extra = per, "craft", pr end
        end
    end
    if not best then
        best, src = math.max(NS.VendorSell(id) * 4, FARM_MIN), "farm"
    end
    memo[key] = { cost = best, src = src, extra = extra }
    return best, src, extra
end
NS.UnitCost = function(id) return UnitCost(id, 0) end

-- Net cost of one craft: materials minus what the result sells back for
local function CraftCost(r)
    if r._cost then return r._cost, r._mats, r._resale, r._farm end
    local mats, farm = RecipeMats(r, 0)
    local resale = r.out and NS.Resale(r.out, r.made or 1) or 0
    r._cost, r._mats, r._resale, r._farm = mats - resale, mats, resale, farm
    return r._cost, mats, resale, farm
end
NS.CraftCost = CraftCost

------------------------------------------------------------------------
-- The plan
------------------------------------------------------------------------
function NS.PlanFor(line)
    local c = NS.Char()
    local p = c.profs[line]
    if not p then
        for k, v in pairs(c.profs) do
            local want
            for _, pr in ipairs(NS.Professions()) do if pr.line == line then want = pr.name end end
            if want and v.name == want then p, line = v, k; break end
        end
    end
    if not p then return nil, "Open this profession's window once so I can read your recipes." end
    local skill, max = NS.SkillFor(line, p.name)
    if not skill then return nil, "You don't have " .. p.name .. " on this character." end
    local target = (NS.db.target and NS.db.target[line]) or max
    if target <= skill then
        return { line = line, name = p.name, skill = skill, max = max, target = target, steps = {}, shop = {},
                 crafts = 0, cost = 0, time = 0, done = true }
    end

    memo = {}
    BuildProducers()
    for _, r in pairs(p.recipes) do r._cost = nil end

    -- usable: learned, or a trainer recipe (no recipe item) you can learn by then
    local pool = {}
    for id, r in pairs(p.recipes) do
        if r.learned or (not r.recipeItem and not r.guess) then
            CraftCost(r)
            pool[#pool + 1] = { id = id, r = r }
        end
    end

    -- Materials you already own are used first, at what you'd get for selling
    -- them (not what they'd cost to buy or gather); beyond that, buy prices.
    local stock, ownVal = {}, {}
    local function Stock(id)
        if stock[id] == nil then stock[id] = NS.Owned(id) end
        return stock[id]
    end
    -- for a slot that accepts several items, draw on the one you have most of
    local function SlotId(g)
        if not g.alts then return g.id end
        local best, bn = g.id, -1
        for _, aid in ipairs(g.alts) do
            local n = Stock(aid)
            if n > bn then best, bn = aid, n end
        end
        return best
    end
    local function OwnValue(id)
        if ownVal[id] == nil then
            -- what you'd give up: its sell value, but never more than replacing it would cost
            local ah = NS.AHPrice(id)
            local sell = ah and math.floor(ah * 0.95) or NS.VendorSell(id)
            ownVal[id] = math.min(sell, (UnitCost(id, 0)))
        end
        return ownVal[id]
    end
    -- cost of `crafts` crafts right now, drawing on your stock first
    -- also returns how many of your own items it uses (to stretch them furthest)
    local function CostNow(r, crafts)
        local total, used = 0, 0
        for _, g in ipairs(r.reagents) do
            local need = g.qty * crafts
            local sid = SlotId(g)
            local mine = math.min(Stock(sid), need)
            used = used + mine
            total = total + mine * OwnValue(sid) + (need - mine) * (UnitCost(g.id, 0))
        end
        local resale = r.out and NS.Resale(r.out, (r.made or 1) * crafts) or 0
        return total - resale, used
    end
    local function Consume(r, crafts)
        for _, g in ipairs(r.reagents) do
            local sid = SlotId(g)
            stock[sid] = math.max(0, Stock(sid) - g.qty * crafts)
        end
    end

    local steps, cur = {}, nil
    local stuck
    for s = skill, target - 1 do
        local best, bestPer, bestChance, bestUsed
        for _, e in ipairs(pool) do
            local r = e.r
            if s >= r.orange then
                local ch = NS.Chance(r, s)
                if ch > 0 then
                    local per, used = CostNow(r, 1 / ch)
                    -- ties: use fewer of your own materials per point, then the faster craft
                    local tol = bestPer and math.max(5, math.abs(bestPer) * 0.1) or 0
                    local better = not bestPer or per < bestPer - tol
                    if not better and math.abs(per - bestPer) <= tol then
                        if used < bestUsed - 0.01 then better = true
                        elseif math.abs(used - bestUsed) <= 0.01 and r.cast < best.r.cast then better = true end
                    end
                    if better then
                        best, bestPer, bestChance, bestUsed = e, per, ch, used
                    end
                end
            end
        end
        if not best then stuck = s; break end
        if cur and cur.id == best.id then
            cur.to = s + 1
        else
            cur = { id = best.id, r = best.r, from = s, to = s + 1, crafts = 0, cost = 0, learn = not best.r.learned }
            steps[#steps + 1] = cur
        end
        cur.crafts = cur.crafts + 1 / bestChance
        cur.cost = cur.cost + bestPer
        Consume(best.r, 1 / bestChance)
    end

    local plan = { line = line, name = p.name, skill = skill, max = max, target = target,
                   steps = steps, stuck = stuck, crafts = 0, cost = 0, time = 0 }

    -- everything you can make right now from your bags, and why it is or isn't a step
    local inPlan = {}
    for _, st in ipairs(steps) do inPlan[st.id] = true end
    local now = {}
    for id, r in pairs(p.recipes) do
        if r.learned then
            local n = math.huge
            for _, g in ipairs(r.reagents) do n = math.min(n, math.floor(NS.SlotBags(g) / math.max(1, g.qty))) end
            if n ~= math.huge and n > 0 then
                local color = NS.Color(r, skill)
                local why
                if inPlan[id] then why = "in the plan"
                elseif color == "gray" then why = "gray: no skill-ups"
                elseif skill < r.orange then why = "needs skill " .. r.orange
                else why = "costs more per point than the plan" end
                now[#now + 1] = { id = id, r = r, n = n, color = color, why = why, inPlan = inPlan[id] }
            end
        end
    end
    local order = { orange = 1, yellow = 1, green = 2, gray = 3 }
    table.sort(now, function(a, b)
        if order[a.color] ~= order[b.color] then return order[a.color] < order[b.color] end
        return a.n > b.n
    end)
    plan.makeNow = now
    for _, st in ipairs(steps) do
        st.n = math.ceil(st.crafts - 0.05)
        st.time = st.n * (st.r.cast or 3)
        plan.crafts = plan.crafts + st.n
        plan.cost = plan.cost + st.cost
        plan.time = plan.time + st.time
    end

    -- shopping list: everything the steps need, minus what you already own.
    -- Owned items get used up step by step; reagents that are cheapest to
    -- craft become "make first" crafts whose materials go on the list.
    local need, via, left, sub = {}, {}, {}, {}
    local function Have(id)
        if left[id] == nil then left[id] = NS.Owned(id) end
        return left[id]
    end
    local function Add(id, n, why)
        need[id] = (need[id] or 0) + n
        if why then via[id] = why end
    end
    for _, st in ipairs(steps) do
        for _, g in ipairs(st.r.reagents) do
            local _, src, extra = UnitCost(g.id, 0)
            local qty = g.qty * st.n
            if src == "craft" and extra then
                local use = math.min(qty, Have(g.id))
                left[g.id] = left[g.id] - use
                Add(g.id, use)
                local toMake = qty - use
                if toMake > 0 then
                    local crafts = math.ceil(toMake / math.max(1, extra.r.made or 1))
                    sub[extra.r.name] = sub[extra.r.name] or { name = extra.r.name, n = 0, out = g.id,
                                                               id = extra.id, line = extra.line }
                    sub[extra.r.name].n = sub[extra.r.name].n + crafts
                    for _, sg in ipairs(extra.r.reagents) do Add(sg.id, sg.qty * crafts, extra.r.name) end
                end
            else
                Add(g.id, qty)
            end
        end
    end
    for _, v in pairs(sub) do
        plan.subcrafts = plan.subcrafts or {}
        table.insert(plan.subcrafts, v)
    end
    local shop = {}
    for id, n in pairs(need) do
        if n > 0 then
            local bags, bank = NS.BagCount(id), NS.BankCount(id)
            local unit, src, extra = UnitCost(id, via[id] and 2 or 0) -- sub-mats: buy, don't craft again
            local buy = math.max(0, n - bags - bank)
            shop[#shop + 1] = { id = id, need = n, bags = bags, bank = bank, buy = buy,
                                unit = unit, src = src, extra = extra, cost = buy * unit, via = via[id] }
        end
    end
    table.sort(shop, function(a, b)
        if (a.buy > 0) ~= (b.buy > 0) then return a.buy > 0 end
        return a.cost > b.cost
    end)
    plan.shop = shop
    plan.buyCost = 0
    for _, e in ipairs(shop) do plan.buyCost = plan.buyCost + e.cost end
    return plan
end
