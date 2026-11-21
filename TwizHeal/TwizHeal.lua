-- TwizHeal: one hotkey heals whoever needs it most, with the right-sized heal.
--
-- Who: you, your party (or raid). Among everyone missing enough health to be
-- worth a heal, the lowest health goes first (role only breaks near-ties: tank,
-- healer, damage dealer). Anyone in real danger (30% or less,
-- /tb-style setting below) jumps the queue whatever their role.
--
-- What: the smallest rank of your direct heal that covers what they're
-- missing (and that you have the mana for); your fast heal (Flash Heal,
-- Regrowth, Flash of Light, Lesser Healing Wave) when someone is in danger.
--
-- The game rules: an addon can't choose a heal target or spell during combat
-- (the cast button is locked once combat starts) and every cast needs a key
-- press or click. So:
--   * out of combat the hotkey heals TwizHeal's pick with the best rank;
--   * in combat the hotkey heals whoever is under your mouse (hover a party
--     bar - the one TwizHeal recommends is highlighted gold), else your
--     friendly target, else the last pick; clicking a bar heals that person.
local ADDON, NS = ...
TwizHeal = NS

local DEFAULTS = { shown = true, danger = 0.30, threshold = 0.89, overheal = 1.10, clickCast = true }
local SPELLS = {
    PRIEST  = { direct = { "Lesser Heal", "Heal", "Greater Heal" }, fast = "Flash Heal", hot = "Renew" },
    DRUID   = { direct = { "Healing Touch" }, fast = "Regrowth", hot = "Rejuvenation" },
    PALADIN = { direct = { "Holy Light" }, fast = "Flash of Light" },
    SHAMAN  = { direct = { "Healing Wave" }, fast = "Lesser Healing Wave" },
}
local ROLE_RANK = { TANK = 1, HEALER = 2, DAMAGER = 3 }
local ROLE_TEXT = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }

local db
local function Print(m) print("|cff8fe08fTwizHeal|r: " .. tostring(m)) end

-- This client can hand addons "secret" values (health, auras... in some fights)
-- that can be shown but not compared or added. Treat those as unknown.
local function safe(v)
    if v == nil then return nil end
    if issecretvalue then
        local ok, s = pcall(issecretvalue, v)
        if ok and s then return nil end
    end
    return v
end
NS.safe = safe

------------------------------------------------------------------------
-- Your heal ranks: { name, rank, label = "Heal(Rank 3)", avg, cost, fast }
------------------------------------------------------------------------
local ranks = {}
local requested
-- rank spell IDs, lowest first, for ranks the spellbook may not list
local RANK_IDS = {
    DRUID = {
        ["Healing Touch"] = { 5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297 },
        ["Regrowth"]      = { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 },
        ["Rejuvenation"]  = { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 },
    },
    PRIEST = {
        ["Lesser Heal"] = { 2050, 2052, 2053 }, ["Heal"] = { 2054, 2055, 6063, 6064 },
        ["Flash Heal"] = { 2061, 9472, 9473, 9474, 10915, 10916, 10917 },
        ["Renew"] = { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315 },
    },
    PALADIN = { ["Holy Light"] = { 635, 639, 647, 1026, 1042, 3472, 10328, 10329, 25292 }, ["Flash of Light"] = { 19750, 19939, 19940, 19941, 19942, 19943 } },
    SHAMAN = { ["Healing Wave"] = { 331, 332, 547, 913, 939, 959, 8005, 10395, 10396, 25357 }, ["Lesser Healing Wave"] = { 8004, 8008, 8010, 10466, 10467, 10468 } },
}

local function SpellBookItems()
    local out = {}
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if info then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    if item and item.spellID then out[#out + 1] = { name = item.name, sub = item.subName, id = item.spellID } end
                end
            end
        end
    elseif GetNumSpellTabs then
        for t = 1, GetNumSpellTabs() do
            local _, _, offset, n = GetSpellTabInfo(t)
            for i = offset + 1, offset + n do
                local name, sub = GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell")
                local _, id = GetSpellBookItemInfo(i, BOOKTYPE_SPELL or "spell")
                if name and id then out[#out + 1] = { name = name, sub = sub, id = id } end
            end
        end
    end
    return out
end

local function Num(x) return x and tonumber((x:gsub(",", ""))) end
-- direct average, HoT total and HoT seconds from the spell's description:
--   "Heal your target for 295 to 341."                       -> 318
--   "Heals the target of 45 damage over 15 sec."              -> 0, 45, 15
--   "Heals a friendly target for 93 to 107 and another 98 damage over 21 sec." -> 100, 98, 21
local function HealAmount(id)
    local text = (C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(id))
        or (GetSpellDescription and GetSpellDescription(id)) or ""
    local avg = 0
    local lo, hi = text:match("(%d[%d,]*) to (%d[%d,]*)")
    if lo then avg = (Num(lo) + Num(hi)) / 2 end
    -- "...175 damage over 12 sec", "...for 32 over 12 sec", "and another 98 over 21 sec"
    local hot, dur = text:match("(%d[%d,]*) damage over (%d+) sec")
    if not hot then hot, dur = text:match("(%d[%d,]*) over (%d+) sec") end
    hot, dur = Num(hot) or 0, tonumber(dur) or 0
    if avg == 0 and hot == 0 then return nil end
    return avg, hot, dur
end

local function Cost(id)
    local costs = C_Spell and C_Spell.GetSpellPowerCost and C_Spell.GetSpellPowerCost(id)
        or (GetSpellPowerCost and GetSpellPowerCost(id))
    local c = costs and costs[1]
    return c and (c.cost or c.minCost) or 0
end

function NS.ReadRanks()
    wipe(ranks)
    NS.needReread = false
    local _, class = UnitClass("player")
    local set = SPELLS[class]
    if not set then return end
    local kindOf = {}
    for _, n in ipairs(set.direct) do kindOf[n] = "direct" end
    kindOf[set.fast] = "fast"
    if set.hot then kindOf[set.hot] = "hot" end
    for _, it in ipairs(SpellBookItems()) do
        local kind = kindOf[it.name]
        if kind then
            local r = tonumber((it.sub or ""):match("(%d+)")) or 1
            local avg, hot, dur = HealAmount(it.id)
            local est = false
            if not avg then
                -- the game hasn't loaded this spell's text yet: ask for it, and guess from the rank meanwhile
                -- ask once per spell; never in a loop
                requested = requested or {}
                if not requested[it.id] and C_Spell and C_Spell.RequestLoadSpellData then
                    requested[it.id] = true
                    pcall(C_Spell.RequestLoadSpellData, it.id)
                end
                est = true
                if kind == "hot" then avg, hot, dur = 0, 60 * r, 12 else avg, hot, dur = 100 * r, 0, 0 end
                NS.needReread = true
            end
            ranks[#ranks + 1] = { name = it.name, rank = r, avg = avg, hot = hot, dur = dur, cost = Cost(it.id),
                kind = kind, fast = kind == "fast", total = avg + hot, est = est,
                -- cast by plain name: this client silently ignores "/cast Spell(Rank 3)" (nothing happens),
                -- and a plain name casts your best rank
                label = it.name, rankText = it.sub, id = it.id }
        end
    end
    -- lower ranks the spellbook doesn't list (it may show only your best): the known rank IDs
    local have = {}
    for _, r in ipairs(ranks) do have[r.id or 0] = true end
    for name, ids in pairs(RANK_IDS[class] or {}) do
        local kind = kindOf[name]
        for rk, id in ipairs(ids) do
            if kind and not have[id] and ((IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id))) then
                local avg, hot, dur = HealAmount(id)
                if avg then
                    ranks[#ranks + 1] = { name = name, rank = rk, avg = avg, hot = hot, dur = dur, cost = Cost(id), kind = kind,
                        fast = kind == "fast", total = avg + hot, est = false, label = name, rankText = "Rank " .. rk, id = id }
                    have[id] = true
                end
            end
        end
    end
    table.sort(ranks, function(a, b) return a.total < b.total end)
end
NS.ranks = ranks

-- smallest heal of a kind ("direct", "fast", "hot"; true = fast for older callers) that
-- covers the deficit within the overheal allowance and that you can afford
local function PickRank(deficit, kind)
    if kind == true then kind = "fast" elseif not kind then kind = "direct" end
    local mana = safe(UnitPower("player", 0)) or 0
    local best
    for _, r in ipairs(ranks) do
        if r.kind == kind and r.cost <= mana then
            best = r
            -- the smallest rank that heals at least everything they're missing (cheapest that's enough)
            if r.total >= deficit then return r end
        end
    end
    if best then return best end
    if kind == "fast" or kind == "hot" then return PickRank(deficit, "direct") end
end
local function Has(kind) for _, r in ipairs(ranks) do if r.kind == kind then return true end end return false end
NS.PickRank = PickRank

------------------------------------------------------------------------
-- Who needs it
------------------------------------------------------------------------
local function Role(unit)
    local r = UnitGroupRolesAssigned and safe(UnitGroupRolesAssigned(unit))
    if r == "TANK" or r == "HEALER" or r == "DAMAGER" then return r end
    -- whoever enemies are attacking is tanking
    local threat = UnitThreatSituation and safe(UnitThreatSituation(unit))
    if threat and threat >= 2 then return "TANK" end
    local _, class = UnitClass(unit)
    if class == "WARRIOR" then return "TANK" end
    if class == "PRIEST" then return "HEALER" end
    if unit == "player" and SPELLS[class] then return "HEALER" end
    return "DAMAGER"
end
NS.Role = Role

local function Units()
    local list = { "player" }
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do local u = "raid" .. i if UnitExists(u) and not UnitIsUnit(u, "player") then list[#list + 1] = u end end
    else
        for i = 1, 4 do local u = "party" .. i if UnitExists(u) then list[#list + 1] = u end end
    end
    return list
end

local function InRange(unit, spell)
    if unit == "player" then return true end
    if UnitInRange then
        local inRange, checked = UnitInRange(unit)
        inRange, checked = safe(inRange), safe(checked)
        if checked then return inRange end
    end
    if spell and C_Spell and C_Spell.IsSpellInRange then
        local r = C_Spell.IsSpellInRange(spell, unit)
        if r ~= nil then return r == true or r == 1 end
    end
    return UnitIsVisible and UnitIsVisible(unit) or true
end

-- your HoTs on a unit: { [spellName] = seconds left }, and the healing they still have to do
-- aura reads: in combat this client can refuse them outright ("cannot be accessed when secret"),
-- which is an error, not a hidden value - treat it as "can't see auras right now"
local function AuraAt(unit, i, filter)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
    if ok then return a end
    return nil, true -- blocked
end

local function MyHoTs(unit)
    local out, incoming, hidden = {}, 0, false
    local _, class = UnitClass("player")
    local set = SPELLS[class] or {}
    local watch = { [set.hot or "-"] = true, [set.fast or "-"] = true }
    -- only YOUR buffs (1.20.1): other people's buffs can be hidden by the game, and one hidden
    -- buff used to make TwizHeal give up on that person (no pre-HoT, no combo)
    for i = 1, 40 do
        local a, blocked = AuraAt(unit, i, "HELPFUL|PLAYER")
        if blocked then hidden = true end
        if not a then break end
        local name, exp, src = safe(a.name), safe(a.expirationTime), safe(a.sourceUnit)
        if not name then hidden = true end
        if name and watch[name] and (src == nil or src == "player" or safe(a.isFromPlayerOrPlayerPet)) then
            local left = exp and exp > 0 and (exp - GetTime()) or 0
            out[name] = math.max(0, left)
            -- the strongest rank you know of it, scaled by the time left
            for j = #ranks, 1, -1 do
                local r = ranks[j]
                if r.name == name and r.hot > 0 and r.dur > 0 then incoming = incoming + r.hot * math.min(1, left / r.dur); break end
            end
        end
    end
    -- still unsure: ask the game for each of your HoTs by name
    if hidden and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local sure = true
        for name in pairs(watch) do
            if name ~= "-" and not out[name] then
                local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, "HELPFUL|PLAYER")
                if not ok then sure = false
                elseif a then
                    local exp = safe(a.expirationTime)
                    out[name] = exp and exp > 0 and math.max(0, exp - GetTime()) or 1
                end
            end
        end
        if sure then hidden = false end
    end
    return out, incoming, hidden
end
NS.MyHoTs = MyHoTs

-- everyone, with health and role: { unit, name, hp, max, pct, deficit, role, inRange }
function NS.Scan()
    local out = {}
    for _, u in ipairs(Units()) do
        if UnitIsConnected(u) and not UnitIsDeadOrGhost(u) then
            local hp, max = safe(UnitHealth(u)), safe(UnitHealthMax(u))
            if not hp or not max then
                NS.hidden = true   -- the game is hiding health right now: TwizHeal can't judge this person
            elseif max > 0 then
                local hots, incoming, hotsHidden = MyHoTs(u)
                -- what's still missing once your HoTs finish ticking
                local deficit = max - hp
                out[#out + 1] = { unit = u, name = safe(UnitName(u)) or u, hp = hp, max = max, pct = hp / max, deficit = deficit,
                    need = math.max(0, deficit - incoming), hots = hots, incoming = incoming, hotsHidden = hotsHidden,
                    role = Role(u), inRange = InRange(u, ranks[1] and ranks[1].name) }
            end
        end
    end
    return out
end

-- the person to heal: anyone in danger first (lowest first); then tanks, healers, damage -
-- among those missing enough to be worth a heal - lowest health first inside each group
function NS.Pick(list)
    list = list or NS.Scan()
    local smallest
    for _, r in ipairs(ranks) do if r.kind == "direct" and (not smallest or r.total < smallest) then smallest = r.total end end
    smallest = smallest or (ranks[1] and ranks[1].total) or 1
    local danger, need, upkeep = {}, {}, {}
    for _, m in ipairs(list) do
        if m.inRange and m.deficit > 0 then
            if m.pct <= (db.danger or 0.3) then danger[#danger + 1] = m
            -- HoTs already on them count: only people still short after those ticks
            elseif m.need > 0 and m.pct <= (db.threshold or 0.89) and m.need >= smallest * 0.5 then
                need[#need + 1] = m
            -- a tank taking damage with none of your HoTs on them: put one up
            -- (only when nobody else needs healing)
            elseif m.role == "TANK" and Has("hot") and not next(m.hots) and m.deficit > 0 and m.pct < 0.99 then
                upkeep[#upkeep + 1] = m
            end
        end
    end
    table.sort(danger, function(a, b) return a.pct < b.pct end)
    if danger[1] then return danger[1], true end
    -- the lowest first (after the HoTs already ticking on them); role only breaks near-ties
    local function eff(m) return m.max and m.max > 0 and (m.max - m.need) / m.max or m.pct end
    table.sort(need, function(a, b)
        local ea, eb = eff(a), eff(b)
        if math.abs(ea - eb) > 0.05 then return ea < eb end
        local ra, rb = ROLE_RANK[a.role] or 3, ROLE_RANK[b.role] or 3
        if ra ~= rb then return ra < rb end
        return ea < eb
    end)
    if need[1] then return need[1], false end
    table.sort(upkeep, function(a, b) return a.pct < b.pct end)
    if upkeep[1] then return upkeep[1], false end
    -- out of combat, nobody hurt: pre-HoT (1.18.0) - one Regrowth and one Rejuvenation on each
    -- person before the pull, tank first, then healer, then damage
    if not InCombatLockdown() then
        local _, class = UnitClass("player")
        local set = SPELLS[class] or {}
        local pre, seen = {}, {}
        local function Missing(hots) return (set.fast and Has("fast") and not hots[set.fast]) or (set.hot and Has("hot") and not hots[set.hot]) end
        for _, m in ipairs(list) do
            seen[m.unit] = true
            if m.inRange and not m.hotsHidden and m.hots and Missing(m.hots) then pre[#pre + 1] = m end
        end
        -- people whose health the game hides: their buffs may still be readable
        for _, u in ipairs(Units()) do
            if not seen[u] and UnitExists(u) and UnitIsConnected(u) and not UnitIsDeadOrGhost(u) and InRange(u, ranks[1] and ranks[1].name) then
                local hots, _, hid = MyHoTs(u)
                if not hid and Missing(hots) then
                    pre[#pre + 1] = { unit = u, name = safe(UnitName(u)) or u, pct = 1, role = Role(u), hots = hots }
                end
            end
        end
        table.sort(pre, function(a, b)
            local ra, rb = ROLE_RANK[a.role] or 3, ROLE_RANK[b.role] or 3
            if ra ~= rb then return ra < rb end
            return a.pct < b.pct
        end)
        if pre[1] then return pre[1], false end
    end
end

-- What to cast on them: { rank, kind, mod } (mod = the modifier that casts it in combat)
--   danger                         -> fast heal (Regrowth / Flash Heal ...), HoT on top next time
--   small need, no HoT of yours    -> HoT (Rejuvenation / Renew): cheapest healing
--   tank with no HoT               -> HoT, so they're always ticking
--   druid, mid need, no Regrowth   -> Regrowth (a direct heal plus its own HoT)
--   anything else                  -> the direct heal that covers what's left
function NS.Choose(m, emergency)
    local hasHot = m.hots and next(m.hots) ~= nil
    local _, class = UnitClass("player")
    local set = SPELLS[class] or {}
    if emergency then
        local r = PickRank(m.need, "fast"); return r, "fast"
    end
    local hotRank = Has("hot") and PickRank(m.need, "hot")
    if hotRank and not (m.hots and m.hots[set.hot]) then
        if m.role == "TANK" and m.pct >= 0.8 then return hotRank, "hot" end   -- keep the tank ticking
        if hotRank.total * (db.overheal or 1.1) >= m.need then return hotRank, "hot" end
    end
    if class == "DRUID" and Has("fast") and not (m.hots and m.hots[set.fast]) and m.pct > 0.4 then
        local r = PickRank(m.need, "fast")
        if r and r.total * (db.overheal or 1.1) >= m.need * 0.8 then return r, "fast" end
    end
    return PickRank(m.need, "direct"), "direct"
end

------------------------------------------------------------------------
-- The hotkey button and party bars
------------------------------------------------------------------------
local frame, btn, bars = nil, nil, {}
local MAXBARS = 5

-- the strongest rank of a kind you can cast (used when health is hidden)
local function Best(kind, step)
    local list = {}
    for _, r in ipairs(ranks) do if r.kind == kind then list[#list + 1] = r end end
    return list[math.max(1, #list - (step or 0))]
end

------------------------------------------------------------------------
-- The rules (no Shift/Ctrl - one key does the right thing)
--   Out of combat (TwizHeal rewrites the key live):
--     you're moving               -> HoT (Rejuvenation / Renew): it's instant
--     they're under half health   -> a real heal sized to the gap (Regrowth if it isn't on them, else Healing Touch)
--     topping off, no HoT of yours -> HoT (cheap, ticks while everyone drinks)
--     topping off, HoT already on -> the smallest direct heal that covers the gap
--   In combat (the game locks the key and hides movement from macros):
--     standing -> fast heal (Regrowth / Flash Heal); moving -> the fast heal can't start, so the
--     next line casts your HoT instead.
------------------------------------------------------------------------
-- moving: the game's start/stop-moving events (reliable even when it hides your speed), or your speed
local function Moving()
    if NS.moving then return true end
    if IsPlayerMoving then local ok, m = pcall(IsPlayerMoving); if ok and safe(m) then return true end end
    local s = GetUnitSpeed and safe(GetUnitSpeed("player"))
    return (s and s > 0) or (IsFalling and IsFalling() and true) or false
end
NS.Moving = Moving

-- Swiftmend: instant, eats a Rejuvenation/Regrowth on the target to heal them a lot at once
local SAVE_PCT = 0.31
local SWIFT_PCT = 0.90 -- Swiftmend at this or under, once your Regrowth + Rejuvenation are on them
local SAVER = { DRUID = "Swiftmend" }
-- under 40%: Nature's Swiftness, then an instant Healing Touch (1.19.0)
local NS_PCT = 0.40
local QUICK = { DRUID = { swift = "Nature's Swiftness", heal = "direct" } }
local function KnowsSpell(name)
    if not name then return false end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok and info then return true end
    end
    if GetSpellInfo then local ok, n = pcall(GetSpellInfo, name); return ok and n ~= nil end
    return false
end
local function SpellReady(name)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return true end
    local ok, cd = pcall(C_Spell.GetSpellCooldown, name)
    if not ok or type(cd) ~= "table" then return true end
    local start, dur = safe(cd.startTime), safe(cd.duration)
    if not start or not dur then return true end
    -- a cooldown no longer than the global cooldown doesn't count
    return dur <= 1.5 or (start + dur - GetTime()) <= 0.2
end
local function Saver()
    local _, class = UnitClass("player")
    local name = SAVER[class]
    if name and KnowsSpell(name) then return { name = name, label = name, kind = "save" } end
end
NS.Saver = Saver
-- Nature's Swiftness, if you know it: { name, heal = the spell kind it makes instant }
local function Quick()
    local _, class = UnitClass("player")
    local q = QUICK[class]
    if q and KnowsSpell(q.swift) and Best(q.heal) then return q end
end
NS.Quick = Quick

-- Tranquility (1.20.0): 3 or more group members under 40% -> channel it. Every TwizHeal key and
-- bar starts with "/stopmacro [channeling:Tranquility]", so pressing them mid-channel never cuts
-- it short: it runs the full channel unless you move or get silenced.
local GROUP_HEAL = { DRUID = "Tranquility" }
local GROUP_PCT, GROUP_COUNT = 0.40, 3
local function GroupHeal()
    local _, class = UnitClass("player")
    local n = GROUP_HEAL[class]
    if n and KnowsSpell(n) then return n end
end
NS.GroupHeal = GroupHeal

-- Read Leyline (Skyborne racial, 1.21.0): your mana at 75% or less (1.22.1) -> cast it when it's off cooldown
-- (+50% health and mana regeneration for 15 sec; more when Attuned at a ley line)
local MANA_PCT = 0.75 -- 75% or less (1.22.1)
local REGEN_NAMES = { "Read Leyline", "Read Ley Line" }
local function Regen()
    for _, n in ipairs(REGEN_NAMES) do if KnowsSpell(n) then return n end end
end
NS.Regen = Regen
local function ManaPct()
    local cur, mx = safe(UnitPower("player", 0)), safe(UnitPowerMax("player", 0))
    if cur and mx and mx > 0 then return cur / mx end
end
NS.ManaPct = ManaPct
local function Stop()
    local g = GroupHeal()
    return g and ("/stopmacro [channeling:" .. g .. "]\n") or ""
end
NS.Stop = Stop
-- how many in the group are under 40% (and in range); nil when the game hides health
function NS.LowCount()
    local now = GetTime()
    if NS.lowAt == now then return NS.lowN end
    local n, hiddenAny = 0, false
    for _, u in ipairs(Units()) do
        if UnitExists(u) and UnitIsConnected(u) and not UnitIsDeadOrGhost(u) then
            local hp, mx = safe(UnitHealth(u)), safe(UnitHealthMax(u))
            if hp and mx and mx > 0 then
                if hp / mx < GROUP_PCT and InRange(u, ranks[1] and ranks[1].name) then n = n + 1 end
            else hiddenAny = true end
        end
    end
    NS.lowAt, NS.lowN = now, (n == 0 and hiddenAny) and nil or n
    return NS.lowN
end

-- The rules, out of combat (where health and buffs can be read):
--   below 31%            -> Swiftmend if your Rejuvenation/Regrowth is on them (instant save);
--                           Rejuvenation first if Swiftmend is ready but nothing is on them yet
--                           (the next press is the Swiftmend); otherwise Regrowth
--   moving               -> Rejuvenation (instant)
--   big gap              -> Regrowth (a big heal now, plus a HoT) - more missing than one
--     (under 60%, or more   Rejuvenation would heal; Healing Touch if Regrowth is already ticking
--      than Rejuv heals)
--   small gap            -> Rejuvenation (cheap, heals over time) if it isn't on them; if it is,
--                           a small Healing Touch for whatever it won't cover
local function OocRule(unit)
    local hot, fast = Best("hot"), Best("fast")
    local u = unit or "player"
    local hots, incoming, hidden = {}, 0, true
    if UnitExists(u) then
        local h, inc, hid = MyHoTs(u)
        hots, incoming, hidden = h, inc or 0, hid
    end
    local cur, mx = safe(UnitHealth(u)), safe(UnitHealthMax(u))
    local pct = cur and mx and mx > 0 and cur / mx or nil
    local need = pct and (mx - cur) or nil
    -- your mana at 75% or less: Read Leyline when it's ready - unless someone is under 40% (save
    -- them first) or you're moving (it has a cast time)
    local regen = Regen()
    if regen and not InCombatLockdown() and not Moving() and SpellReady(regen) and (ManaPct() or 1) <= MANA_PCT
        and not (pct and pct < NS_PCT) and (NS.LowCount() or 0) == 0 then
        return { name = regen, label = regen, kind = "self" }, "mana"
    end
    -- health hidden but your buffs readable, out of combat: pre-HoT anyway (1.20.1)
    if pct == nil and not hidden and not InCombatLockdown() and UnitExists(u) and not UnitIsDeadOrGhost(u) then
        if fast and not hots[fast.name] and not Moving() then return fast, "pre-HoT" end
        if hot and not hots[hot.name] then return hot, "pre-HoT" end
    end
    -- the game hides their health: it could be 95%, so no automatic heal (the instant and
    -- emergency keys still cast on demand)
    if pct == nil then return nil, "hidden" end
    local moving = Moving()
    -- 3+ under 40%: Tranquility (channeled; not while moving)
    local g = GroupHeal()
    if g and not moving and SpellReady(g) and (NS.LowCount() or 0) >= GROUP_COUNT then
        return { name = g, label = g, kind = "group" }, "Tranquility"
    end
    -- under 40%: Nature's Swiftness, then Healing Touch - instant (1.19.0). Sized to what's
    -- missing after your HoTs (they're low, so usually a big rank).
    local q = Quick()
    if q and pct < NS_PCT and SpellReady(q.swift) then
        local left0 = math.max(0, (need or 0) - (incoming or 0))
        local r = PickRank(left0 > 0 and left0 or (need or 0), q.heal) or Best(q.heal)
        if r then return setmetatable({ swift = q.swift }, { __index = r }), "Nature's Swiftness" end
    end
    local hasHot = not hidden and hot and hots[hot.name]
    local hasFast = not hidden and fast and hots[fast.name]
    -- no 89% limit out of combat (1.23.0): a press always heals. The smallest Healing Touch that
    -- covers what's missing after your HoTs (rank 1 at full health)
    local function Small()
        local gap = math.max(1, (need or 0) - (incoming or 0))
        return PickRank(gap, "direct") or Best("direct") or hot or fast, "heal"
    end
    -- PRE-HoT (1.18.0): out of combat, above 89%, one Regrowth then one Rejuvenation (your top
    -- ranks - they're there to soak the pull); after that, a small Healing Touch
    if pct > (db and db.threshold or 0.89) then
        if not hidden and not InCombatLockdown() then
            if fast and not hasFast and not moving then return fast, "pre-HoT" end
            if hot and not hasHot then return hot, "pre-HoT" end
        end
        if moving and hot then return hot, "moving" end
        return Small()
    end
    local left = need and math.max(0, need - (incoming or 0)) or nil

    -- THE COMBO (Alan's rule): Regrowth, then Rejuvenation right after, then Swiftmend at 90% or under
    -- 1. your Regrowth is on them but Rejuvenation isn't: Rejuvenation (instant)
    if hasFast and hot and not hasHot then
        return (left and left > 0 and PickRank(left, "hot")) or hot, "after Regrowth"
    end
    -- 2. your Rejuvenation (or Regrowth) on them, 90% or under, Swiftmend ready: Swiftmend
    if pct <= SWIFT_PCT and (hasHot or hasFast) then
        local saver = Saver()
        if saver and SpellReady(saver.name) then return saver, "Swiftmend" end
    end
    -- above 89% (/th threshold): not worth starting a new heal
    -- 3. moving: Regrowth can't be cast - Rejuvenation (the combo picks up from there)
    if moving and hot then return (need and PickRank(need, "hot")) or hot, "moving" end
    -- 4. start the combo: Regrowth sized to the gap
    if fast and not hasFast then
        return PickRank(left or need, "fast") or fast, pct < SAVE_PCT and "low" or "Regrowth first"
    end
    -- 5. combo done (Swiftmend on cooldown or not learned): Healing Touch for what's still missing
    if left and left > 0 then
        return PickRank(left, "direct") or Best("direct"), "Regrowth on"
    end
    if hot and not hasHot then return hot, "topping off" end
    return Small()
end
NS.OocRule = OocRule

local function Chain(c, unit, only)
    if only then return ("[%s@%s]"):format(c, unit) end
    return ("[%s@mouseover,help,nodead][%s@target,help,nodead][%s@%s]"):format(c, c, c, unit)
end
-- ooc = the spell the rules picked for out of combat (nil = do nothing out of combat)
-- only = heal exactly that unit (TwizHeal's own bars)
-- Downranked heals: "/cast Healing Touch(Rank 3)" does nothing on this client, so a lower rank
-- is cast by spell ID through a hidden secure spell button that the key /clicks.
local castButtons = {}
local function CastButton(key)
    if castButtons[key] then return castButtons[key] end
    local b = CreateFrame("Button", "TwizHealCast" .. key, UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "spell")
    b:Hide()
    castButtons[key] = b
    return b
end
-- a group token for a mouseover/target that's in your group (stays right after the mouse moves)
local function StableUnit(u)
    if u ~= "mouseover" and u ~= "target" then return u end
    if UnitIsUnit then
        if UnitIsUnit(u, "player") then return "player" end
        local prefix, n = IsInRaid() and "raid" or "party", IsInRaid() and 40 or 4
        for i = 1, n do local g = prefix .. i; if UnitExists(g) and UnitIsUnit(u, g) then return g end end
    end
    return u
end
local function Downranked(r)
    if not r or not r.id or not r.kind then return false end
    local best = Best(r.kind)
    return best and best ~= r and (r.total or 0) < (best.total or 0)
end
NS.Downranked = Downranked

-- In combat: our own spell cycle (Regrowth, Rejuvenation, Healing Touch, Healing Touch),
-- run by the game's secure code on each press, so it can cast a smaller Healing Touch rank
-- (/castsequence only takes names = always your top rank). Each press advances; a new
-- target or a new fight starts over at Regrowth; the target is your mouseover, else friendly
-- target, else the fallback - decided at the moment you press.
local secureHeader
local cycleButtons = {}
-- the Healing Touch rank used in combat (health can't be read there): /th combatrank N, or
-- the smallest rank that heals about 20% of the biggest health pool, below your top rank
local function CombatDirect()
    local direct = {}
    for _, r in ipairs(ranks) do if r.kind == "direct" and r.id then direct[#direct + 1] = r end end
    if #direct == 0 then return nil end
    table.sort(direct, function(a, b) return a.total < b.total end)
    if db and db.combatRank then
        for _, r in ipairs(direct) do if r.rank == db.combatRank and r.name == direct[#direct].name then return r end end
    end
    local biggest = 0
    for _, u in ipairs(Units()) do local m = safe(UnitHealthMax(u)); if m and m > biggest then biggest = m end end
    -- automatic: about 20% of the biggest health pool, but never your top rank (that one's for
    -- out of combat, where TwizHeal can see a big gap) - /th combatrank N to choose
    local pick = direct[math.max(1, math.ceil(#direct / 2))]
    if biggest > 0 then
        pick = direct[#direct]
        for _, r in ipairs(direct) do if r.total >= biggest * 0.2 then pick = r; break end end
    end
    if pick == direct[#direct] and #direct > 1 then pick = direct[#direct - 1] end
    return pick
end
NS.CombatDirect = CombatDirect
local function CycleButton(key, unitopts, ids)
    if not (SecureHandlerWrapScript and CreateFrame) then return nil end
    local b = cycleButtons[key]
    if not b then
        if not secureHeader then secureHeader = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate") end
        b = CreateFrame("Button", "TwizHealCycle" .. key, UIParent, "SecureActionButtonTemplate")
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "spell")
        b:Hide()
        -- restricted code: only the game's secure functions exist here (no GetTime, no string
        -- splitting), so the spell IDs sit in attributes cycleid1..N
        local ok = pcall(SecureHandlerWrapScript, b, "OnClick", secureHeader, [[
            local count = self:GetAttribute("cyclecount") or 0
            if count < 1 then return end
            local unit = SecureCmdOptionParse(self:GetAttribute("unitopts"))
            local n = self:GetAttribute("cyclen") or 0
            -- a different target starts the combo over at Regrowth
            if unit ~= self:GetAttribute("cycleunit") then n = 0 end
            n = n % count + 1
            self:SetAttribute("cyclen", n)
            self:SetAttribute("cycleunit", unit)
            self:SetAttribute("spell", self:GetAttribute("cycleid" .. n))
            self:SetAttribute("unit", unit)
        ]])
        if not ok then return nil end
        cycleButtons[key] = b
    end
    if b:GetAttribute("cycleids") ~= ids then
        b:SetAttribute("cycleids", ids)
        local n = 0
        for id in ids:gmatch("%d+") do n = n + 1; b:SetAttribute("cycleid" .. n, tonumber(id)) end
        b:SetAttribute("cyclecount", n)
    end
    -- out of combat: each fight starts the combo at Regrowth
    if not InCombatLockdown() and (b:GetAttribute("cyclen") or 0) ~= 0 then b:SetAttribute("cyclen", 0) end
    if b:GetAttribute("unitopts") ~= unitopts then b:SetAttribute("unitopts", unitopts) end
    return b
end
NS.CycleButton = CycleButton

-- noCombat: the key's own macro when no bar is hovered. In combat the game hides health, so the
-- key can't check 90% itself: it casts nothing unless you hover the empty part of a bar (see the
-- mouse blockers in the bar build), which only exists when that person is under 90%.
local function SmartMacro(unit, ooc, only, oocUnit, castKey, noCombat)
    local fast, hot = Best("fast"), Best("hot")
    local combat = fast or Best("direct", 1) or Best("direct")
    local _, class = UnitClass("player")
    local lines = {}
    local stop = Stop()
    if stop ~= "" then lines[#lines + 1] = stop:sub(1, -2) end
    -- druids: drop cat/bear/travel form first (heals can't be cast in them)
    if class == "DRUID" then lines[#lines + 1] = "/cancelform [form]" end
    if ooc and (ooc.kind == "group" or ooc.kind == "self") then
        lines[#lines + 1] = "/cast [nocombat] " .. ooc.label
        ooc = nil -- no single-target heal behind it (moving -> the Rejuvenation line below)
        lines.group = true
    end
    if ooc and ooc.swift then lines[#lines + 1] = "/cast [nocombat] " .. ooc.swift end
    if ooc and Downranked(ooc) and (oocUnit or only) then
        -- a smaller rank that still covers what they're missing: cheaper
        local b = CastButton(castKey or "Key")
        b:SetAttribute("spell", ooc.id)
        b:SetAttribute("unit", StableUnit(only and unit or oocUnit))
        local keyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
        lines[#lines + 1] = "/click [nocombat] " .. b:GetName() .. (keyDown and " LeftButton 1" or "")
    elseif ooc then
        lines[#lines + 1] = "/cast " .. Chain("nocombat,", unit, only) .. " " .. ooc.label
    end
    -- in combat (no reading auras or health): Regrowth, Rejuvenation, then Healing Touch on the
    -- next presses; a new target or new fight starts at Regrowth again. (Swiftmend stays on the
    -- emergency key: in a sequence, a Swiftmend on cooldown would stall it.)
    local direct = Best("direct")
    local cd = CombatDirect()
    local cyc
    if noCombat then combat = nil end
    if combat and fast and fast.id and cd and combat == fast then
        -- the combo: Regrowth, Rejuvenation, Swiftmend (if learned; a press on cooldown just moves
        -- on), then Healing Touch
        local ids = { fast.id }
        if hot and hot.id then ids[#ids + 1] = hot.id end
        local saver = Saver()
        local sid = saver and C_Spell and C_Spell.GetSpellInfo and (function() local ok, i = pcall(C_Spell.GetSpellInfo, saver.name); return ok and i and i.spellID end)()
        if sid then ids[#ids + 1] = sid end
        ids[#ids + 1] = cd.id
        if not sid then ids[#ids + 1] = cd.id end
        local opts = only and unit or ("[@mouseover,help,nodead] mouseover; [@target,help,nodead] target; " .. unit)
        cyc = CycleButton(castKey or "Key", opts, table.concat(ids, ","))
    end
    -- in combat, Read Leyline first whenever it's off cooldown (1.22.0): the game hides nothing
    -- here, but the key is locked, so it can't check your mana - at most once per 2 min. On
    -- cooldown the line is skipped and the heal goes out (its "not ready" error is hidden).
    -- 1.23.2: only when your mana is 75% or less as the fight starts (the key is locked in combat,
    -- so this is the last moment it can check)
    local regen = not noCombat and Regen()
    if regen and (ManaPct() or 1) > MANA_PCT then regen = nil end
    if regen and (cyc or combat) then lines[#lines + 1] = "/cast [combat] " .. regen end
    if cyc then
        local keyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
        lines[#lines + 1] = "/click [combat] " .. cyc:GetName() .. (keyDown and " LeftButton 1" or "")
    elseif combat and fast and direct and combat == fast then
        -- Regrowth, then Rejuvenation right after (instant), then Healing Touch
        local seq = { fast.label }
        if hot then seq[#seq + 1] = hot.label end
        seq[#seq + 1] = direct.label; seq[#seq + 1] = direct.label
        lines[#lines + 1] = "/castsequence " .. Chain("combat,", unit, only) .. " reset=12 " .. table.concat(seq, ", ")
    elseif combat then
        lines[#lines + 1] = "/cast " .. Chain("combat,", unit, only) .. " " .. combat.label
    end
    -- moving fallback, in and out of combat: if the cast above can't start because you're moving
    -- (Regrowth, Healing Touch), this line casts your instant HoT instead
    -- (out of combat only when the rules picked a heal: nobody above 89% gets one)
    if hot and noCombat then
        if ooc then lines[#lines + 1] = "/cast " .. Chain("nocombat,", unit, only) .. " " .. hot.label end
    elseif hot then lines[#lines + 1] = "/cast " .. Chain(ooc and "" or "combat,", unit, only) .. " " .. hot.label end
    return table.concat(lines, "\n")
end
NS.SmartMacro = SmartMacro

-- the instant heal: your HoT (Rejuvenation / Renew), castable while moving, in or out of combat
local function InstantMacro(unit, only)
    local hot = Best("hot")
    local spell = hot or Best("fast") or Best("direct")
    if not spell then return "" end
    local _, class = UnitClass("player")
    local pre = Stop() .. (class == "DRUID" and "/cancelform [form]\n" or "")
    return pre .. "/cast " .. Chain("", unit, only) .. " " .. spell.label
end
NS.InstantMacro = InstantMacro

-- the emergency key: Rejuvenation then Swiftmend (two instant presses) - works in combat, where
-- the game won't tell an addon who's low. Without Swiftmend: Rejuvenation then Regrowth.
local function EmergencyMacro(unit, only)
    local hot, fast = Best("hot"), Best("fast")
    local saver = Saver()
    local second = saver and saver.label or (fast and fast.label)
    if not hot or not second then return InstantMacro(unit, only) end
    local _, class = UnitClass("player")
    local pre = Stop() .. (class == "DRUID" and "/cancelform [form]\n" or "")
    return pre .. "/castsequence " .. Chain("", unit, only) .. " reset=6 " .. hot.label .. ", " .. second
end
NS.EmergencyMacro = EmergencyMacro

-- the Nature's Swiftness key (1.19.0): Nature's Swiftness, then your biggest Healing Touch -
-- instant. For combat, where the game hides health: hover a bar that's red / under 40% and press
-- it. (Nature's Swiftness on cooldown: the press does nothing - use the emergency key.)
-- Without Nature's Swiftness it works like the emergency key.
local function QuickMacro(unit, only)
    local q = Quick()
    if not q then return EmergencyMacro(unit, only) end
    local heal = Best(q.heal)
    local _, class = UnitClass("player")
    local pre = Stop() .. (class == "DRUID" and "/cancelform [form]\n" or "")
    return pre .. "/cast " .. q.swift .. "\n/cast " .. Chain("", unit, only) .. " " .. heal.label
end
NS.QuickMacro = QuickMacro

-- the Tranquility key (1.20.0): for combat, where the game hides health - when 3 or more bars
-- show the red under-40% strip, press it. Pressing again mid-channel does nothing.
local function GroupMacro()
    local g = GroupHeal()
    if not g then return "" end
    local _, class = UnitClass("player")
    return Stop() .. (class == "DRUID" and "/cancelform [form]\n" or "") .. "/cast " .. g
end
NS.GroupMacro = GroupMacro

local function SetMacro(b, text)
    if b and b:GetAttribute("macrotext") ~= text then b:SetAttribute("macrotext", text) end
end

local function Build()
    local Skin = NS.Skin
    frame = CreateFrame("Frame", "TwizHealFrame", UIParent, "BackdropTemplate")
    frame:SetSize(220, 40 + MAXBARS * 22)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -260)
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton"); frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(); db.pos = { p, rp, x, y }
    end)
    if db.pos then frame:ClearAllPoints(); frame:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4]) end
    Skin.Panel(frame)
    frame.title = Skin.Text(frame, "title"); frame.title:SetPoint("TOPLEFT", 10, -9); frame.title:SetText("TwizHeal")
    frame.next = Skin.Text(frame, "small"); frame.next:SetPoint("LEFT", frame.title, "RIGHT", 8, 0); frame.next:SetPoint("RIGHT", -28, 0)
    local close = Skin.IconButton(frame, "x", "Hide (/th to show)", function() if not InCombatLockdown() then db.shown = false; frame:Hide() end end)
    close:SetPoint("TOPRIGHT", -6, -5)
    -- no title bar: just the bars (drag a bar to move, /th window to hide)
    frame.title:Hide(); frame.next:Hide(); close:Hide()

    -- resize: drag the grip in the bottom-right corner (out of combat - the game locks secure frames)
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(140, 50, 600, 500)
    elseif frame.SetMinResize then frame:SetMinResize(140, 50); frame:SetMaxResize(600, 500) end
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(14, 14); grip:SetPoint("BOTTOMRIGHT", -2, 2); grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        if InCombatLockdown() then return end
        frame.sizing = true; frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        if not frame.sizing then return end
        frame:StopMovingOrSizing(); frame.sizing = false
        -- bar height from the new height, spread over the people shown
        local n = math.max(1, frame.shownBars or 1)
        db.barH = NS.HealthHeightFor(frame:GetHeight(), n)
        db.width = math.floor(frame:GetWidth())
        NS.Layout()
        local p, _, rp, x, y = frame:GetPoint(); db.pos = { p, rp, x, y }
    end)
    frame:SetScript("OnSizeChanged", function() if frame.sizing then NS.Layout(true) end end)

    -- party bars: hover one and press your TwizHeal key to heal that person (works in combat too:
    -- a secure hover handler swaps the key to that bar's heal); clicking a bar heals as well
    for i = 1, MAXBARS do
        local b = CreateFrame("Button", "TwizHealBar" .. i, frame, "SecureUnitButtonTemplate,SecureHandlerEnterLeaveTemplate,BackdropTemplate")
        b:SetSize(200, 20)
        b:SetPoint("TOPLEFT", 10, -30 - (i - 1) * 22)
        b:RegisterForDrag("LeftButton") -- dragging a bar moves the window
        b:SetScript("OnDragStart", function() if not InCombatLockdown() then frame:StartMoving() end end)
        b:SetScript("OnDragStop", function() frame:GetScript("OnDragStop")(frame) end)
        b:RegisterForClicks("AnyUp")
        b:SetAttribute("type", "macro")
        b:SetAttribute("unit", i == 1 and "player" or ("party" .. (i - 1)))
        if b.SetBackdrop then
            b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            b:SetBackdropColor(0.165, 0.184, 0.220, 1); b:SetBackdropBorderColor(0.173, 0.192, 0.227, 1)
        end
        b.bar = CreateFrame("StatusBar", nil, b)
        b.bar:SetPoint("TOPLEFT", 1, -1); b.bar:SetPoint("BOTTOMRIGHT", -1, 1)
        b.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        b.bar:SetMinMaxValues(0, 1)
        -- role icon, then the name
        b.role = b.bar:CreateTexture(nil, "OVERLAY"); b.role:SetSize(12, 12); b.role:SetPoint("LEFT", 3, 0)
        b.name = b.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.name:SetPoint("LEFT", b.role, "RIGHT", 3, 0)
        -- status border (disease, poison, curse, magic, rooted...) drawn over the bar
        b.status = CreateFrame("Frame", nil, b, "BackdropTemplate")
        b.status:SetPoint("TOPLEFT", -1, 1); b.status:SetPoint("BOTTOMRIGHT", 1, -1)
        b.status:SetFrameLevel(b:GetFrameLevel() + 5)
        if b.status.SetBackdrop then b.status:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 }) end
        b.status:Hide()
        b.pct = b.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.pct:SetPoint("RIGHT", -4, 0)
        -- incoming heals (yours and others'): a light green bar from the end of their health,
        -- scaled to their max health, so it shows how far the heals will fill them
        b.bar:SetClipsChildren(true)
        b.incBar = CreateFrame("StatusBar", nil, b.bar)
        b.incBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        b.incBar:SetStatusBarColor(0.50, 1, 0.62, 0.45)
        b.incBar:SetMinMaxValues(0, 1); b.incBar:SetValue(0)
        local fill = b.bar:GetStatusBarTexture()
        b.incBar:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0); b.incBar:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
        b.incBar:SetWidth(198)
        b.inc = b.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.inc:SetPoint("RIGHT", b.pct, "LEFT", -4, 0)
        b.inc:SetTextColor(0.45, 0.95, 0.58)
        -- shields (Power Word: Shield...): a pale blue bar after the incoming heals, the shield's
        -- icon and amount, and a soft blue glow inside the bar
        b.absBar = CreateFrame("StatusBar", nil, b.bar)
        b.absBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        b.absBar:SetStatusBarColor(0.75, 0.9, 1, 0.75)
        b.absBar:SetMinMaxValues(0, 1); b.absBar:SetValue(0)
        local incFill = b.incBar:GetStatusBarTexture()
        b.absBar:SetPoint("TOPLEFT", incFill, "TOPRIGHT", 0, 0); b.absBar:SetPoint("BOTTOMLEFT", incFill, "BOTTOMRIGHT", 0, 0)
        b.absBar:SetWidth(198)
        b.glow = CreateFrame("Frame", nil, b.bar, "BackdropTemplate"); b.glow:SetAllPoints(b.bar)
        if b.glow.SetBackdrop then b.glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }); b.glow:SetBackdropBorderColor(0.6, 0.85, 1, 0.9) end
        b.glow:Hide()
        b.absIcon = b.bar:CreateTexture(nil, "OVERLAY"); b.absIcon:SetSize(11, 11); b.absIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92); b.absIcon:Hide()
        b.abs = b.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.abs:SetTextColor(0.7, 0.88, 1)
        b.abs:SetPoint("RIGHT", b.inc, "LEFT", -4, 0)
        b.absIcon:SetPoint("RIGHT", b.abs, "LEFT", -2, 0)
        -- text and icon above the incoming bar
        b.over = CreateFrame("Frame", nil, b.bar); b.over:SetAllPoints(b.bar); b.over:SetFrameLevel(b.absBar:GetFrameLevel() + 3)
        b.glow:SetFrameLevel(b.absBar:GetFrameLevel() + 2)
        for _, r in ipairs({ b.role, b.name, b.pct, b.inc, b.abs, b.absIcon }) do r:SetParent(b.over) end
        -- all text white with a dark outline, readable on any bar color
        for _, fs in ipairs({ b.name, b.pct, b.inc, b.abs }) do
            fs:SetTextColor(1, 1, 1)
            local font, size = fs:GetFont()
            if font then fs:SetFont(font, size or 10, "OUTLINE") end
            fs.baseFont = font
            fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1)
            if fs.SetWordWrap then fs:SetWordWrap(false) end
            if fs.SetMaxLines then fs:SetMaxLines(1) end
        end
        b.name:SetJustifyH("LEFT")
        -- mana (always, even in cat/bear form) and energy/rage under the health bar
        for _, k in ipairs({ "mana", "power" }) do
            local pb = CreateFrame("StatusBar", nil, b)
            pb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            pb:SetMinMaxValues(0, 1); pb:SetValue(0)
            pb.bg = pb:CreateTexture(nil, "BACKGROUND"); pb.bg:SetAllPoints(); pb.bg:SetColorTexture(0.05, 0.05, 0.07, 1)
            b[k] = pb
        end
        b.mana:SetStatusBarColor(0.0, 0.44, 0.87)
        -- in combat (health hidden): an invisible mouse blocker over the whole bar for anyone at 90%
        -- or more (1.17.1). b.guard is a hidden bar the game fills from the real health through a
        -- step curve: full at 90%+, empty under 90%. The blocker is pinned to its fill, so it
        -- covers the whole bar or nothing - under 90% the whole bar can be hovered and clicked.
        -- (No curve support: fall back to blocking the green part and the last 10%.)
        local lvl = b.over:GetFrameLevel() + 5
        -- a red strip along the bottom of the bar when they're under 40% and you have Nature's
        -- Swiftness: hover them and press the Nature's Swiftness key (works with hidden health)
        b.low = CreateFrame("StatusBar", nil, b.bar)
        b.low:SetPoint("BOTTOMLEFT", b.bar, "BOTTOMLEFT", 0, 0); b.low:SetPoint("BOTTOMRIGHT", b.bar, "BOTTOMRIGHT", 0, 0)
        b.low:SetHeight(3)
        b.low:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        b.low:SetStatusBarColor(1, 0.1, 0.1, 1)
        b.low:SetMinMaxValues(0, 1); b.low:SetValue(0)
        b.low:SetFrameLevel(b.over:GetFrameLevel() + 1)
        b.guard = CreateFrame("StatusBar", nil, b)
        b.guard:SetAllPoints(b.bar)
        b.guard:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        b.guard:SetStatusBarColor(0, 0, 0, 0)
        b.guard:SetMinMaxValues(0, 1); b.guard:SetValue(0)
        b.blockFill = CreateFrame("Frame", nil, b)
        b.blockFill:SetPoint("TOPLEFT", b.bar, "TOPLEFT", 0, 0)
        b.blockTop = CreateFrame("Frame", nil, b)
        b.blockTop:SetPoint("TOPRIGHT", b.bar, "TOPRIGHT", 0, 0); b.blockTop:SetPoint("BOTTOMRIGHT", b.bar, "BOTTOMRIGHT", 0, 0)
        b.blockTop:SetWidth(20)
        if NS.GuardCurve() then
            b.blockFill:SetPoint("BOTTOMRIGHT", b.guard:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
            b.useGuard = true
        else
            b.blockFill:SetPoint("BOTTOMRIGHT", b.bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        end
        for _, bl in ipairs({ b.blockFill, b.blockTop }) do
            bl:SetFrameLevel(lvl); bl:EnableMouse(true); bl:Hide()
        end
        b:Hide()
        bars[i] = b
    end

    btn = CreateFrame("Button", "TwizHealButton", frame, "SecureActionButtonTemplate")
    btn:SetSize(1, 1); btn:SetPoint("BOTTOMLEFT"); btn:SetAlpha(0)
    btn:RegisterForClicks("AnyUp", "AnyDown") -- acts once, on press or release per the "cast on key down" option
    btn:SetAttribute("type", "macro")
    -- tell you when a press didn't heal (out of range, can't cast while moving...)
    btn:HookScript("PostClick", function() if NS.OnPress then NS.OnPress() end end)
    -- when the key or a bar was pressed (its errors are checked as they happen, before PostClick)
    btn:HookScript("PreClick", function() NS.clickAt = GetTime(); NS.FightCount("key") end)
    for _, b in ipairs(bars) do b:HookScript("PreClick", function() NS.clickAt = GetTime(); NS.FightCount("bar") end) end
    for _, b in ipairs(bars) do
        if b.SetFrameRef then b:SetFrameRef("key", btn) end
        b:SetAttribute("_onenter", [[
            local key = self:GetFrameRef("key")
            local m, m2, m3 = self:GetAttribute("healmacro"), self:GetAttribute("healmacro2"), self:GetAttribute("healmacro3")
            local m4 = self:GetAttribute("healmacro4")
            if key and m4 then key:SetAttribute("macrotext4", m4) end
            if key and m3 then key:SetAttribute("macrotext3", m3) end
            if key and m then key:SetAttribute("macrotext1", m) end
            if key and m2 then key:SetAttribute("macrotext2", m2) end
        ]])
        b:SetAttribute("_onleave", [[
            local key = self:GetFrameRef("key")
            if key then
                key:SetAttribute("macrotext1", key:GetAttribute("basemacro"))
                key:SetAttribute("macrotext2", key:GetAttribute("basemacro2"))
                key:SetAttribute("macrotext3", key:GetAttribute("basemacro3"))
                key:SetAttribute("macrotext4", key:GetAttribute("basemacro4"))
            end
        ]])
        b:HookScript("OnEnter", function(self) NS.hoverUnit = self:GetAttribute("unit") end)
        b:HookScript("OnLeave", function() NS.hoverUnit = nil end)
    end
    frame:Hide() -- shown by the first successful update
end

-- layout: each row = health bar + a thin power row (mana | energy) under it; no title bar
local TOP = 6
local function PowerH(h) return math.max(3, math.floor(h / 4)) end
local function RowH(h) return h + PowerH(h) + 1 end
function NS.HealthHeightFor(height, n)
    local row = (height - 2 * TOP) / math.max(1, n) - 2
    return math.max(10, math.min(60, math.floor((row - 1) * 0.8)))
end
-- live = while dragging the grip (keep the height the mouse sets)
function NS.Layout(live)
    if not frame or InCombatLockdown() then return end
    local n = math.max(1, frame.shownBars or 1)
    local w = live and frame:GetWidth() or (db.width or 220)
    local h = live and NS.HealthHeightFor(frame:GetHeight(), n) or (db.barH or 20)
    if not live then frame:SetWidth(w) end
    local ph = PowerH(h)
    for i, b in ipairs(bars) do
        b:SetSize(math.max(60, w - 12), RowH(h))
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", 6, -TOP - (i - 1) * (RowH(h) + 2))
        b.bar:ClearAllPoints(); b.bar:SetPoint("TOPLEFT", 1, -1); b.bar:SetPoint("BOTTOMRIGHT", -1, ph + 1)
        if b.incBar then b.incBar:SetWidth(math.max(60, w - 12) - 2); b.absBar:SetWidth(math.max(60, w - 12) - 2) end
        if b.blockTop then b.blockTop:SetWidth(math.max(1, ((math.max(60, w - 12) - 2) * (1 - SWIFT_PCT)))) end
        b.powerH = ph
        b.laid = nil -- power bars re-anchor on the next update
        -- tall bars: buff icons on top, numbers underneath; short bars: everything on one line
        b.twoLine = h >= 22
        local fsz = b.twoLine and math.floor(h * 0.4) or math.floor(h * 0.62)
        fsz = math.max(7, math.min(14, fsz))
        b.iconSize = b.twoLine and math.max(8, math.min(16, math.floor(h * 0.42))) or math.max(7, math.min(16, h - 4))
        for _, fs in ipairs({ b.name, b.pct, b.inc, b.abs }) do
            if fs.baseFont then pcall(fs.SetFont, fs, fs.baseFont, fsz, "OUTLINE") end
        end
        b.role:SetSize(math.max(8, fsz + 2), math.max(8, fsz + 2))
    end
    if not live then frame:SetHeight(2 * TOP + n * (RowH(h) + 2) - 2) end
end

local POWER_COLOR = { [0] = { 0.0, 0.44, 0.87 }, [1] = { 0.78, 0.25, 0.25 }, [2] = { 1, 0.5, 0.25 }, [3] = { 1, 0.82, 0 }, [6] = { 0, 0.82, 1 } }
local MANA_CLASS = { DRUID = true, PRIEST = true, MAGE = true, WARLOCK = true, PALADIN = true, SHAMAN = true, HUNTER = true, EVOKER = true, MONK = false }
-- mana always (if their class has it, even shapeshifted); their current power too when it isn't mana
local function DrawPower(b, unit)
    local _, class = UnitClass(unit)
    local ptype = safe(UnitPowerType and UnitPowerType(unit)) or 0
    local hasMana = MANA_CLASS[class] or ptype == 0
    local other = ptype ~= 0 and ptype or nil
    local mode = (hasMana and other) and "both" or hasMana and "mana" or other and "power" or "none"
    if b.laid ~= mode then
        b.laid = mode
        local ph = b.powerH or 5
        for _, pb in ipairs({ b.mana, b.power }) do pb:ClearAllPoints(); pb:Hide() end
        local function place(pb, l, r)
            pb:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", l, 1); pb:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", r, ph + 1); pb:Show()
        end
        if mode == "both" then
            b.mana:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1); b.mana:SetPoint("TOPRIGHT", b, "BOTTOM", -1, ph + 1); b.mana:Show()
            b.power:SetPoint("BOTTOMLEFT", b, "BOTTOM", 1, 1); b.power:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", -1, ph + 1); b.power:Show()
        elseif mode == "mana" then place(b.mana, 1, -1)
        elseif mode == "power" then place(b.power, 1, -1) end
    end
    if hasMana then
        pcall(b.mana.SetMinMaxValues, b.mana, 0, UnitPowerMax(unit, 0) or 1)
        pcall(b.mana.SetValue, b.mana, UnitPower(unit, 0) or 0)
    end
    if other then
        local c = POWER_COLOR[other] or POWER_COLOR[3]
        b.power:SetStatusBarColor(c[1], c[2], c[3])
        pcall(b.power.SetMinMaxValues, b.power, 0, UnitPowerMax(unit, other) or 1)
        pcall(b.power.SetValue, b.power, UnitPower(unit, other) or 0)
    end
end
NS.DrawPower = DrawPower

------------------------------------------------------------------------
-- Role icons and status borders
------------------------------------------------------------------------
local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }
local ROLE_COORDS = { TANK = { 0, 19 / 64, 22 / 64, 41 / 64 }, HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 }, DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 } }
function NS.SetRoleIcon(tex, role)
    role = role == "DPS" and "DAMAGER" or role
    if not ROLE_COORDS[role] then tex:Hide(); return end
    if tex.role == role then tex:Show(); return end
    tex.role = role
    local ok = tex.SetAtlas and pcall(tex.SetAtlas, tex, ROLE_ATLAS[role])
    if not ok then
        tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTROLES")
        tex:SetTexCoord(unpack(ROLE_COORDS[role]))
    end
    tex:Show()
end

-- border colors, most important first (curses and poisons first: druids can remove those)
NS.STATUS_COLORS = {
    Curse   = { 0.64, 0.19, 0.79 }, -- purple
    Poison  = { 0.00, 0.80, 0.20 }, -- green
    Disease = { 0.76, 0.52, 0.20 }, -- brown
    Magic   = { 0.20, 0.60, 1.00 }, -- blue
    Rooted  = { 1.00, 1.00, 1.00 }, -- white
    Stunned = { 1.00, 0.85, 0.10 }, -- yellow (stun, fear, sheep, silence...)
    Other   = { 0.90, 0.30, 0.20 }, -- red (any other harmful effect)
}
local STATUS_ORDER = { "Curse", "Poison", "Disease", "Magic", "Rooted", "Stunned", "Other" }
local CONTROL = { ROOT = "Rooted", STUN = "Stunned", STUN_MECHANIC = "Stunned", FEAR = "Stunned", FEAR_MECHANIC = "Stunned",
    CHARM = "Stunned", CONFUSE = "Stunned", POSSESS = "Stunned", SILENCE = "Stunned", PACIFY = "Stunned", PACIFYSILENCE = "Stunned", DISARM = "Stunned" }
local ROOT_WORDS = { "root", "frost nova", "entangl", "net", "snare", "web", "freez", "frozen" }

-- what's on them: the most important kind wins
function NS.StatusOf(unit)
    local found = {}
    for i = 1, 40 do
        local a = AuraAt(unit, i, "HARMFUL")
        if not a then break end
        local kind = safe(a.dispelName)
        if kind and NS.STATUS_COLORS[kind] and kind ~= "Rooted" and kind ~= "Stunned" and kind ~= "Other" then
            found[kind] = true
        else
            local name = safe(a.name)
            local lname = type(name) == "string" and name:lower() or ""
            local rooted = false
            for _, w in ipairs(ROOT_WORDS) do if lname:find(w, 1, true) then rooted = true; break end end
            found[rooted and "Rooted" or "Other"] = true
        end
    end
    -- your own crowd control, from the loss-of-control list (stun, fear, root...)
    if UnitIsUnit and UnitIsUnit(unit, "player") and C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCount then
        local n = safe(C_LossOfControl.GetActiveLossOfControlDataCount()) or 0
        for i = 1, n do
            local d = C_LossOfControl.GetActiveLossOfControlData(i)
            local t = d and safe(d.locType)
            if t and CONTROL[t] then found[CONTROL[t]] = true end
        end
    end
    for _, k in ipairs(STATUS_ORDER) do if found[k] then return k end end
end

function NS.DrawStatus(b, unit)
    local kind = NS.StatusOf(unit)
    if kind then
        local c = NS.STATUS_COLORS[kind]
        b.status:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        b.status:Show()
    else
        b.status:Hide()
    end
    b.statusKind = kind
end

-- incoming heals on someone: everyone's casts (the game's heal prediction), else your own HoTs
function NS.DrawIncoming(b, unit)
    local inc = UnitGetIncomingHeals and UnitGetIncomingHeals(unit)
    local n = safe(inc)
    if inc == nil or (n and n == 0) then
        local _, hot = MyHoTs(unit)
        if hot and hot > 0 then inc, n = math.floor(hot), math.floor(hot) end
    end
    pcall(b.incBar.SetMinMaxValues, b.incBar, 0, UnitHealthMax(unit) or 1)
    pcall(b.incBar.SetValue, b.incBar, inc or 0)
    if n and n > 0 then
        b.inc:SetText(("+%d"):format(n)); b.inc:Show()
    else
        -- none, or hidden by the game (the bar still shows hidden amounts; the number can't be read)
        b.inc:Hide()
    end
    b.incoming = n
end

-- health as exact numbers and percent: "1234 / 2000  62%"
function NS.DrawHPText(b, unit)
    b.hpShort = nil
    if UnitIsDeadOrGhost(unit) then b.pct:SetText(""); return end
    local cur, mx = UnitHealth(unit), UnitHealthMax(unit)
    local c, m = safe(cur), safe(mx)
    if c and m and m > 0 then
        b.pct:SetText(("%d / %d  %d%%"):format(c, m, c / m * 100 + 0.5))
        b.hpShort = ("%d%%"):format(c / m * 100 + 0.5)
    else
        -- hidden by the game: let the game print the numbers (fontstrings may show hidden values)
        local ok = pcall(b.pct.SetFormattedText, b.pct, "%d / %d", cur, mx)
        if ok and UnitHealthPercent then
            local okP, p = pcall(UnitHealthPercent, unit, true, CurveConstants and CurveConstants.ScaleTo100)
            if okP and p then ok = pcall(b.pct.SetFormattedText, b.pct, "%d / %d  %d%%", cur, mx, p) end
        end
        if not ok then b.pct:SetText("") end
    end
end

-- shields on someone: the game's absorb total, plus the shield aura's icon
local SHIELDS = { ["Power Word: Shield"] = true, ["Ice Barrier"] = true, ["Mana Shield"] = true, ["Sacrifice"] = true,
    ["Fire Ward"] = true, ["Frost Ward"] = true, ["Shadow Ward"] = true, ["Divine Aegis"] = true, ["Earth Shield"] = false,
    ["Greater Fire Protection Potion"] = false }
function NS.DrawAbsorb(b, unit)
    local abs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)
    local n = safe(abs)
    local icon, auraName
    for i = 1, 40 do
        local a = AuraAt(unit, i, "HELPFUL")
        if not a then break end
        local name = safe(a.name)
        if name and SHIELDS[name] then icon, auraName = safe(a.icon) or 135940, name; break end
    end
    pcall(b.absBar.SetMinMaxValues, b.absBar, 0, UnitHealthMax(unit) or 1)
    pcall(b.absBar.SetValue, b.absBar, abs or 0)
    local shielded = (n and n > 0) or icon ~= nil
    b.glow:SetShown(shielded)
    if icon then b.absIcon:SetTexture(icon); b.absIcon:Show() else b.absIcon:Hide() end
    if n and n > 0 then b.abs:SetText(("%d"):format(n)); b.abs:Show()
    elseif icon then b.abs:SetText(""); b.abs:Show()
    else b.abs:Hide() end
    b.absorb, b.shieldAura = n, auraName
end

-- your buffs on them (Mark of the Wild, Thorns, Rejuvenation...): small icons in the bar's
-- top-right corner, right to left, with a sweep showing the time left
local MAXICONS = 6
function NS.DrawMyBuffs(b, unit)
    b.buffIcons = b.buffIcons or {}
    local size = b.iconSize or 10
    local n = 0
    for i = 1, 40 do
        local a = AuraAt(unit, i, "HELPFUL|PLAYER")
        if not a or n >= MAXICONS then break end
        local src = safe(a.sourceUnit)
        if src == nil or src == "player" or src == "pet" then
            n = n + 1
            local ic = b.buffIcons[n]
            if not ic then
                ic = CreateFrame("Frame", nil, b.over)
                ic.tex = ic:CreateTexture(nil, "ARTWORK"); ic.tex:SetAllPoints(); ic.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                ic.cd = CreateFrame("Cooldown", nil, ic, "CooldownFrameTemplate"); ic.cd:SetAllPoints()
                if ic.cd.SetHideCountdownNumbers then ic.cd:SetHideCountdownNumbers(true) end
                if ic.cd.SetDrawEdge then ic.cd:SetDrawEdge(false) end
                ic.cd:SetReverse(true)
                b.buffIcons[n] = ic
            end
            ic:SetSize(size, size)
            pcall(ic.tex.SetTexture, ic.tex, a.icon)
            local dur, exp = safe(a.duration), safe(a.expirationTime)
            if dur and exp and dur > 0 then pcall(ic.cd.SetCooldown, ic.cd, exp - dur, dur); ic.cd:Show() else ic.cd:Hide() end
            ic.name = safe(a.name)
            ic:Show()
        end
    end
    for k = n + 1, #b.buffIcons do b.buffIcons[k]:Hide() end
    b.myBuffs = n
end

-- lay out a bar's texts and icons so nothing overlaps: right side (from the edge) health
-- numbers, incoming, shield; buff icons on top (tall bars) or in line (short bars); the
-- name gets whatever room is left and is cut short rather than drawn over anything
local function TextW(fs)
    if not fs:IsShown() then return 0 end
    local ok, w = pcall(fs.GetStringWidth, fs)
    w = ok and safe(w) or 0
    return type(w) == "number" and w or 0
end
local function ArrangeOnce(b)
    local W = safe(b.bar:GetWidth())
    if not W or W <= 0 then W = (safe(b:GetWidth()) or 200) - 2 end
    local two = b.twoLine
    local size = b.iconSize or 10
    local nIcons = b.myBuffs or 0
    local textY = two and "BOTTOMRIGHT" or "RIGHT"
    local yOff = two and 1 or 0
    local x = 3
    local function place(region, w)
        region:ClearAllPoints()
        region:SetPoint(textY, b.over, textY, -x, yOff)
        x = x + w + 4
    end
    place(b.pct, TextW(b.pct))
    if b.inc:IsShown() then place(b.inc, TextW(b.inc)) end
    if b.abs:IsShown() then place(b.abs, TextW(b.abs)) end
    if b.absIcon:IsShown() then
        b.absIcon:SetSize(size, size); place(b.absIcon, size)
    end
    local textEdge = x
    -- buff icons
    if nIcons > 0 then
        local ix = two and 1 or x
        for i = 1, nIcons do
            local ic = b.buffIcons[i]
            ic:ClearAllPoints()
            if two then ic:SetPoint("TOPRIGHT", b.over, "TOPRIGHT", -ix, -1)
            else ic:SetPoint("RIGHT", b.over, "RIGHT", -ix, 0) end
            ix = ix + size + 1
        end
        if not two then x = ix + 3 end
        if two then textEdge = math.max(textEdge, ix + 3) end
    end
    -- the name fills what's left on the left
    local left = 3 + (b.role:IsShown() and (b.role:GetWidth() + 3) or 0)
    local room = W - left - math.max(x, textEdge)
    b.name:SetWidth(math.max(10, room))
    return room
end
function NS.Arrange(b)
    -- too tight for the name: show just the percent instead of "800 / 2000  40%"
    if ArrangeOnce(b) < 45 and b.hpShort then
        b.pct:SetText(b.hpShort)
        ArrangeOnce(b)
    end
end

local function HealthColor(pct)
    if pct < 0.35 then return 1, 0.4, 0.4 elseif pct < 0.7 then return 1, 0.69, 0.4 end
    return 0.16, 0.78, 0.30
end

-- When the game hides health (in combat), addons can't compare it - but the game can still
-- turn it into a color for us: a color curve evaluated by the game (green -> orange -> red).
-- The bar shows who's low at a glance; hover the reddest bar and press your key.
local hpCurve
-- 1 at 90%+ health, 0 under: drives the combat mouse blocker (1.17.1)
local guardCurve
function NS.GuardCurve(again)
    if again then guardCurve = nil end
    if guardCurve ~= nil then return guardCurve end
    guardCurve = false
    if not (C_CurveUtil and C_CurveUtil.CreateCurve and UnitHealthPercent) then return false end
    local ok, c = pcall(C_CurveUtil.CreateCurve)
    if not ok or not c then return false end
    if not (c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step) then return false end
    if not pcall(c.SetType, c, Enum.LuaCurveType.Step) then return false end
    for _, pt in ipairs({ { 0, 0 }, { SWIFT_PCT + 0.001, 1 }, { 1, 1 } }) do
        if not pcall(c.AddPoint, c, pt[1], pt[2]) then return false end
    end
    guardCurve = c
    return c
end
function NS.DrawGuard(b, unit, pct)
    if not b.guard then return end
    if pct then b.guard:SetValue(pct > SWIFT_PCT and 1 or 0); return end
    local c = NS.GuardCurve()
    local ok, v = false, nil
    if c then ok, v = pcall(UnitHealthPercent, unit, true, c) end
    -- can't tell (1.23.1): leave the bar clickable - a heal too many beats a heal that never comes
    if not ok or v == nil or not pcall(b.guard.SetValue, b.guard, v) then b.guard:SetValue(0); NS.guardFailed = true end
end
-- 1 under 40% health, 0 from 40% up: the red "use Nature's Swiftness" strip (1.19.0)
local lowCurve
function NS.LowCurve(again)
    if again then lowCurve = nil end
    if lowCurve ~= nil then return lowCurve end
    lowCurve = false
    if not (C_CurveUtil and C_CurveUtil.CreateCurve and UnitHealthPercent and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step) then return false end
    local ok, c = pcall(C_CurveUtil.CreateCurve)
    if not ok or not c or not pcall(c.SetType, c, Enum.LuaCurveType.Step) then return false end
    for _, pt in ipairs({ { 0, 1 }, { NS_PCT, 0 }, { 1, 0 } }) do
        if not pcall(c.AddPoint, c, pt[1], pt[2]) then return false end
    end
    lowCurve = c
    return c
end
function NS.DrawLow(b, unit, pct)
    if not b.low then return end
    if not (Quick() or GroupHeal()) or UnitIsDeadOrGhost(unit) then b.low:SetValue(0); return end
    if pct then b.low:SetValue(pct < NS_PCT and 1 or 0); return end
    local c = NS.LowCurve()
    local ok, v = false, nil
    if c then ok, v = pcall(UnitHealthPercent, unit, false, c) end
    if not ok or v == nil or not pcall(b.low.SetValue, b.low, v) then b.low:SetValue(0) end
end
local function CurveColorBar(b, unit)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and UnitHealthPercent and CreateColor) then return false end
    if not hpCurve then
        local ok, c = pcall(C_CurveUtil.CreateColorCurve)
        if not ok or not c then return false end
        if c.SetType and Enum and Enum.LuaCurveType then pcall(c.SetType, c, Enum.LuaCurveType.Linear) end
        for _, pt in ipairs({ { 0, 1, 0.2, 0.2 }, { 0.35, 1, 0.4, 0.4 }, { 0.6, 1, 0.69, 0.4 }, { 0.89, 0.16, 0.78, 0.30 }, { 1, 0.16, 0.78, 0.30 } }) do
            pcall(c.AddPoint, c, pt[1], CreateColor(pt[2], pt[3], pt[4]))
        end
        hpCurve = c
    end
    local ok, col = pcall(UnitHealthPercent, unit, true, hpCurve)
    if not ok or not col or not col.GetRGB then return false end
    local tex = b.bar:GetStatusBarTexture()
    return tex and pcall(function() tex:SetVertexColor(col:GetRGB()) end) or false
end
NS.CurveColorBar = CurveColorBar

-- the "LOWEST" marker: a pulsing red frame around the lowest bar (when health can be read)
local function LowMark(b)
    if b.lowMark then return b.lowMark end
    local f = CreateFrame("Frame", nil, b, "BackdropTemplate")
    f:SetPoint("TOPLEFT", -3, 3); f:SetPoint("BOTTOMRIGHT", 3, -3)
    f:SetFrameLevel(b:GetFrameLevel() + 8)
    if f.SetBackdrop then f:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 }); f:SetBackdropBorderColor(1, 0.25, 0.25, 1) end
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("RIGHT", f, "LEFT", -2, 0); f.label:SetText("|cffff5050LOWEST >|r")
    local t = 0
    f:SetScript("OnUpdate", function(self, e) t = t + e; self:SetAlpha(0.55 + 0.45 * math.abs(math.sin(t * 4))) end)
    f:Hide()
    b.lowMark = f
    return f
end

local Update
local reported
function NS.Update()
    if not db then return end
    NS.hidden = false
    local ok, err = pcall(Update)
    if not ok and not reported then
        reported = true
        Print("something went wrong drawing the window (please tell Alan/Claude): " .. tostring(err))
    end
end

Update = function()
    if not frame then Build() end
    local list = NS.Scan()
    local pick, emergency = NS.Pick(list)
    local inCombat = InCombatLockdown()
    -- bars
    local byUnit = {}
    for _, m in ipairs(list) do byUnit[m.unit] = m end
    -- the lowest one worth a heal (only when health can be read)
    local lowest
    for _, m in ipairs(list) do
        if m.inRange and m.pct <= (db.threshold or 0.89) and not UnitIsDeadOrGhost(m.unit) and (not lowest or m.pct < lowest.pct) then lowest = m end
    end
    local shown = 0
    for i, b in ipairs(bars) do
        local unit = b:GetAttribute("unit")
        local m = byUnit[unit]
        if UnitExists(unit) then
            shown = i
            local pct = m and m.pct or 1
            -- the bar takes the game's numbers directly, so it fills even when they're hidden from addons
            pcall(b.bar.SetMinMaxValues, b.bar, 0, UnitHealthMax(unit) or 1)
            pcall(b.bar.SetValue, b.bar, UnitHealth(unit) or 0)
            pcall(NS.DrawIncoming, b, unit)
            pcall(NS.DrawGuard, b, unit, m and m.pct)
            pcall(NS.DrawLow, b, unit, m and m.pct)
            if m then b.bar:SetStatusBarColor(HealthColor(pct))
            elseif not CurveColorBar(b, unit) then b.bar:SetStatusBarColor(0.45, 0.5, 0.55) end -- unknown: grey
            pcall(DrawPower, b, unit)
            local dead = UnitIsDeadOrGhost(unit)
            b.name:SetText(("%s%s"):format(safe(UnitName(unit)) or unit, dead and " dead" or ""))
            pcall(NS.SetRoleIcon, b.role, Role(unit))
            pcall(NS.DrawStatus, b, unit)
            pcall(NS.DrawMyBuffs, b, unit)
            pcall(NS.Arrange, b)
            pcall(NS.DrawHPText, b, unit)
            pcall(NS.DrawAbsorb, b, unit)
            local lm = LowMark(b)
            if lowest and lowest.unit == unit and #list > 1 then lm:Show() else lm:Hide() end
            local picked = pick and pick.unit == unit
            if b.SetBackdropBorderColor then
                if picked then b:SetBackdropBorderColor(0.941, 0.769, 0.361, 1) else b:SetBackdropBorderColor(0.173, 0.192, 0.227, 1) end
            end
            b:SetAlpha((m and m.inRange) and 1 or 0.45)
            if not inCombat then b:Show() end
        elseif not inCombat then
            b:Hide()
        end
    end
    -- what the hotkey will do
    -- who the key heals (1.24.1): the TwizHeal bar you hover, else the lowest (the pick; the tank when
    -- health is hidden) - exactly as if you clicked their bar. Your target and mouseover no longer
    -- take over the heal-the-lowest key (the instant / emergency keys still follow them).
    local fallback = pick and pick.unit
    if not fallback then
        fallback = "player"
        if NS.hidden then for _, u in ipairs(Units()) do if u ~= "player" and Role(u) == "TANK" then fallback = u; break end end end
    end
    local function friend(u) return UnitExists(u) and not UnitIsDeadOrGhost(u) and (not UnitCanAssist or UnitCanAssist("player", u)) end
    local who = (NS.hoverUnit and UnitExists(NS.hoverUnit) and NS.hoverUnit) or fallback
    local ooc, why
    ooc, why = OocRule(who)
    if inCombat then
        local fast, hot = Best("fast") or Best("direct", 1), Best("hot")
        frame.next:SetText(fast and ("|cfff0c45c%s|r%s"):format(fast.name, hot and (" |cff9aa1ab(moving: " .. hot.name .. ")|r") or "") or "no heal known")
    elseif ooc then
        frame.next:SetText(("%s%s|r -> %s |cff9aa1ab(%s)|r"):format((why == "low" or (why or ""):find("^save")) and "|cffff8060" or "|cfff0c45c", ooc.label,
            UnitIsUnit and UnitIsUnit(who, "player") and "you" or (safe(UnitName(who)) or who), why))
    else
        frame.next:SetText(NS.hidden and "|cff9aa1abhealth hidden by the game - no auto heals (instant / emergency keys still cast)|r" or "|cff8fe08feveryone's fine|r")
    end
    NS.ooc, NS.oocWhy = ooc, why
    if not inCombat then NS.fallback = fallback end
    if not inCombat then
        local base, base2, base3 = SmartMacro(who, ooc, true, who, "Key"), InstantMacro(fallback), EmergencyMacro(fallback)
        btn:SetAttribute("basemacro", base); btn:SetAttribute("basemacro2", base2); btn:SetAttribute("basemacro3", base3)
        local base4 = QuickMacro(fallback)
        btn:SetAttribute("basemacro4", base4)
        local m5 = GroupMacro()
        if btn:GetAttribute("macrotext5") ~= m5 then btn:SetAttribute("macrotext5", m5) end
        local hovered, hovered2, hovered3, hovered4
        -- each bar keeps its own heals: left-click / main key = the rules, right-click / instant
        -- key = your HoT; hovering a bar points both keys at that person
        for i, b in ipairs(bars) do
            local unit = b:GetAttribute("unit")
            if UnitExists(unit) then
                local r, w = OocRule(unit)
                local m, m2, m3 = SmartMacro(unit, r, true, unit, "Bar" .. i), InstantMacro(unit, true), EmergencyMacro(unit, true)
                if b:GetAttribute("healmacro3") ~= m3 then b:SetAttribute("healmacro3", m3) end
                if b:GetAttribute("macrotext3") ~= m3 then b:SetAttribute("macrotext3", m3) end -- middle-click a bar
                local m4 = QuickMacro(unit, true)
                if b:GetAttribute("healmacro4") ~= m4 then b:SetAttribute("healmacro4", m4) end
                if b:GetAttribute("macrotext4") ~= m4 then b:SetAttribute("macrotext4", m4) end -- mouse button 4 on a bar
                if b:GetAttribute("macrotext5") ~= m5 then b:SetAttribute("macrotext5", m5) end -- mouse button 5: Tranquility
                if NS.hoverUnit == unit then hovered4 = m4 end
                SetMacro(b, m)
                if b:GetAttribute("macrotext2") ~= m2 then b:SetAttribute("macrotext2", m2) end
                if b:GetAttribute("healmacro") ~= m then b:SetAttribute("healmacro", m) end
                if b:GetAttribute("healmacro2") ~= m2 then b:SetAttribute("healmacro2", m2) end
                if NS.hoverUnit == unit then hovered, hovered2, hovered3 = m, m2, m3 end
            end
        end
        local k1, k2 = hovered or base, hovered2 or base2
        if btn:GetAttribute("macrotext1") ~= k1 then btn:SetAttribute("macrotext1", k1) end
        if btn:GetAttribute("macrotext2") ~= k2 then btn:SetAttribute("macrotext2", k2) end
        local k3 = hovered3 or base3
        if btn:GetAttribute("macrotext3") ~= k3 then btn:SetAttribute("macrotext3", k3) end
        local k4 = hovered4 or base4
        if btn:GetAttribute("macrotext4") ~= k4 then btn:SetAttribute("macrotext4", k4) end
    end
    if not inCombat then
        if frame.shownBars ~= shown or not frame.laidOut then frame.shownBars, frame.laidOut = shown, true; NS.Layout() end
        frame:SetShown(db.shown and #ranks > 0)
    end
    NS.pick = pick
end

------------------------------------------------------------------------
-- The game's own party and raid frames
--   Hover a frame and press your TwizHeal key (or the TwizBuff key) - that works on any
--   unit frame. And click-casting right on the frames:
--     Alt + click   the TwizHeal key's rules on that person
--   Plain clicks still target / open the menu as before.
------------------------------------------------------------------------
local applied, pending = setmetatable({}, { __mode = "k" }), {}
local STATIC = { "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame" }
for i = 1, 4 do STATIC[#STATIC + 1] = "PartyMemberFrame" .. i end
for i = 1, 5 do STATIC[#STATIC + 1] = "CompactPartyFrameMember" .. i end
for i = 1, 40 do STATIC[#STATIC + 1] = "CompactRaidFrame" .. i end
for g = 1, 8 do for m = 1, 5 do STATIC[#STATIC + 1] = ("CompactRaidGroup%dMember%d"):format(g, m) end end

local function ApplyFrame(f)
    if not f or type(f) ~= "table" or not f.SetAttribute or not db or not db.clickCast then return end
    if InCombatLockdown() then pending[f] = true; return end
    if #ranks == 0 then return end
    -- the frame you click is your mouseover, so this runs the TwizHeal key's rules on it
    local keyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    pcall(f.SetAttribute, f, "alt-type1", "macro")
    pcall(f.SetAttribute, f, "alt-macrotext1", "/click TwizHealButton" .. (keyDown and " LeftButton 1" or ""))
    for _, k in ipairs({ "alt-type2", "alt-ctrl-type1", "alt-ctrl-type2" }) do pcall(f.SetAttribute, f, k, nil) end
    applied[f] = true
end

function NS.ApplyClickCast()
    if not db or not db.clickCast or InCombatLockdown() then return end
    for _, name in ipairs(STATIC) do ApplyFrame(_G[name]) end
    if PartyFrame and PartyFrame.MemberFrame1 then
        for i = 1, 4 do ApplyFrame(PartyFrame["MemberFrame" .. i]) end
    end
    for f in pairs(ClickCastFrames or {}) do ApplyFrame(f) end
    for f in pairs(pending) do ApplyFrame(f); pending[f] = nil end
end

-- the game registers its unit frames in ClickCastFrames for click-cast addons: catch new ones
do
    local existing = ClickCastFrames or {}
    if not getmetatable(existing) then
        ClickCastFrames = setmetatable({}, {
            __newindex = function(t, frame, v)
                rawset(t, frame, v)
                if v then ApplyFrame(frame) end
            end,
        })
        for f, v in pairs(existing) do ClickCastFrames[f] = v end
    end
end
if hooksecurefunc and CompactUnitFrame_SetUpFrame then
    hooksecurefunc("CompactUnitFrame_SetUpFrame", function(frame) ApplyFrame(frame) end)
end

------------------------------------------------------------------------
-- Feedback: after a press, say in chat if the heal didn't go out, and why
------------------------------------------------------------------------
local press = { at = 0 }
-- Read Leyline on cooldown makes every combat press say "Spell is not ready yet": hide that one
-- message right after a TwizHeal press (1.22.0); every other error still shows
function NS.HideNotReady()
    if NS.errHooked or not UIErrorsFrame or not UIErrorsFrame.GetScript then return end
    local orig = UIErrorsFrame:GetScript("OnEvent")
    if not orig then return end
    NS.errHooked = true
    local notReady = {}
    for _, k in ipairs({ "SPELL_FAILED_NOT_READY", "ERR_SPELL_COOLDOWN", "ERR_ABILITY_COOLDOWN" }) do
        local v = _G[k]; if type(v) == "string" then notReady[v] = true end
    end
    UIErrorsFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "UI_ERROR_MESSAGE" and Regen() and GetTime() - (NS.clickAt or 0) < 0.5 then
            local _, msg = ...
            msg = safe(msg)
            if msg and (notReady[msg] or msg:lower():find("not ready")) then return end
        end
        return orig(self, event, ...)
    end)
end
local function Who()
    local function friend(u) return UnitExists(u) and not UnitIsDeadOrGhost(u) and (not UnitCanAssist or UnitCanAssist("player", u)) end
    local u = NS.hoverUnit and UnitExists(NS.hoverUnit) and NS.hoverUnit or NS.fallback or "player"
    if UnitIsUnit and UnitIsUnit(u, "player") then return "you" end
    return safe(UnitName(u)) or u
end
function NS.OnPress()
    local now = GetTime()
    if now - press.at < 0.15 then return end -- key down + key up = one press
    press.at, press.who, press.done, press.said, press.err, press.failed = now, Who(), false, false, nil, false
end
local fb = CreateFrame("Frame")
for _, e in ipairs({ "UI_ERROR_MESSAGE", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED" }) do
    pcall(fb.RegisterEvent, fb, e)
end
-- errors are held until the press settles: a heal that went out wins over the "another action
-- in progress" a second macro line can raise
fb:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" then NS.FightCount("casts")
    elseif event == "UI_ERROR_MESSAGE" and GetTime() - (NS.clickAt or 0) < 0.5 then NS.FightCount("err", type(a2) == "string" and a2 or a1) end
    if GetTime() - press.at > 0.6 or press.said then return end
    if event == "UI_ERROR_MESSAGE" then
        local msg = safe(type(a2) == "string" and a2 or a1)
        if type(msg) == "string" and msg ~= "" and not press.err then press.err = msg end
    elseif a1 == "player" then
        if event == "UNIT_SPELLCAST_FAILED" then press.failed = true else press.done = true end
    end
end)
-- "Healing Touch (Rank 3) -> Bob": a line above the party window each time you cast a heal,
-- so you can see which rank went out (/th castinfo turns it off)
local castLine, castFade
local function RankOf(id)
    for _, r in ipairs(ranks) do if r.id == id then return r.rank end end
    local _, class = UnitClass("player")
    for _, ids in pairs(RANK_IDS[class] or {}) do
        for rk, rid in ipairs(ids) do if rid == id then return rk end end
    end
end
local function HealName(id)
    local name = C_Spell and C_Spell.GetSpellName and safe(C_Spell.GetSpellName(id))
    if not name and GetSpellInfo then name = safe((GetSpellInfo(id))) end
    if not name then return nil end
    for _, r in ipairs(ranks) do if r.name == name then return name end end
    if name == "Swiftmend" then return name end
end
function NS.ShowCast(id, target)
    if db and db.castInfo == false then return end
    id = safe(id)
    if type(id) ~= "number" then return end
    local name = HealName(id)
    if not name then return end
    local rk = RankOf(id)
    if not castLine then
        castLine = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        local font, size = castLine:GetFont()
        if font then castLine:SetFont(font, (size or 12) + 1, "OUTLINE") end
        castFade = CreateFrame("Frame")
        NS.castLine = castLine
    end
    castLine:ClearAllPoints()
    if frame and frame:IsShown() then castLine:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 4, 4)
    else castLine:SetPoint("CENTER", UIParent, "CENTER", 0, -140) end
    target = safe(target)
    castLine:SetText(("|cff8fe08f%s|r%s%s"):format(name, rk and (" |cfff0c45c(Rank " .. rk .. ")|r") or "",
        (type(target) == "string" and target ~= "") and (" |cff9aa1ab->|r " .. target) or ""))
    castLine:SetAlpha(1); castLine:Show()
    local t = 0
    castFade:SetScript("OnUpdate", function(self, e)
        t = t + e
        if t > 3 then castLine:SetAlpha(math.max(0, 1 - (t - 3))) end
        if t > 4 then castLine:Hide(); self:SetScript("OnUpdate", nil) end
    end)
end
local castEv = CreateFrame("Frame")
castEv:RegisterEvent("UNIT_SPELLCAST_SENT")
castEv:SetScript("OnEvent", function(_, _, unit, target, _, spellID)
    if unit == "player" then pcall(NS.ShowCast, spellID, target) end
end)

local fbTick = CreateFrame("Frame")
fbTick:SetScript("OnUpdate", function()
    if press.at == 0 or press.said or GetTime() - press.at < 0.6 then return end
    press.said = true
    if press.done or (db and db.feedback == false) then return end
    -- pressed during Tranquility: the key held off on purpose
    if UnitChannelInfo and GroupHeal() and safe((UnitChannelInfo("player"))) == GroupHeal() then return end
    local who = press.who or "?"
    local whose = who == "you" and "your" or (who .. "'s")
    -- the same note over and over is spam: each kind of message at most every 20 seconds
    NS.lastNote = NS.lastNote or {}
    local function Once(key) local t = NS.lastNote[key]; if t and GetTime() - t < 20 then return false end; NS.lastNote[key] = GetTime(); return true end
    -- a spell on cooldown in the combat cycle (Swiftmend) is expected: the next press moves on
    if press.err and press.err:lower():find("not ready") then return end
    if press.err then
        if Once("err" .. press.err) then Print(("couldn't heal %s: %s"):format(who, press.err)) end
        if press.err:lower():find("moving") and not NS.toldInstant then
            NS.toldInstant = true
            Print("while moving, use your instant-heal key (Options > Keybindings > AddOns > TwizHeal > \"Instant heal\"), or right-click a bar - it casts Rejuvenation, which works on the run.")
        end
    elseif press.failed then
        Print(("the heal on %s failed (range, line of sight or mana?)"):format(who))
    elseif NS.oocWhy == "hidden" and not InCombatLockdown() then
        if Once("hidden") then
            Print(("the game is hiding %s health right now, so TwizHeal can't tell if a heal is needed - no heal. Your instant or emergency key heals anyway."):format(whose))
        end
    elseif NS.oocWhy == "fine" and not InCombatLockdown() then
        if Once("fine" .. who) then
            Print(("%s %s above %d%% health with your HoTs up - no heal needed."):format(who == "you" and "you" or who, who == "you" and "are" or "is", (db.threshold or 0.89) * 100 + 0.5))
        end
    elseif InCombatLockdown() then
        if Once("combat") then
            Print(("key pressed in combat but nothing was cast on %s - out of range, line of sight, or moving?"):format(who))
        end
    else
        Print(("key pressed but nothing was cast on %s - %s"):format(who,
            #ranks == 0 and "no heals found (/th ranks)" or "/th test shows what the key does"))
    end
end)

------------------------------------------------------------------------
-- Events, slash
------------------------------------------------------------------------
-- the combat mouse blockers on every bar (see the bar build)
-- 1.23.1: only the whole-bar blocker driven by the game's health curve. Without that curve (or
-- with /th guard off) nothing blocks the bars: the old fallback could cover every bar in combat
-- and swallow your clicks.
function NS.SetBlockers(on)
    for _, b in ipairs(bars) do
        if b.blockTop then b.blockTop:Hide() end
        if b.blockFill then
            if on and b.useGuard and db and db.combatGuard ~= false then b.blockFill:Show() else b.blockFill:Hide() end
        end
    end
end

-- after a fight where your TwizHeal presses healed nobody: one line saying what happened
local fight = {}
function NS.FightStart() fight = { key = 0, bar = 0, casts = 0, errs = {} } end
function NS.FightEnd()
    local f = fight
    fight = {}
    if not f.key or (f.key + f.bar) < 3 or f.casts > 0 then return end
    local errs = {}
    for msg, n in pairs(f.errs) do errs[#errs + 1] = ("%s x%d"):format(msg, n) end
    Print(("last fight: %d key presses, %d bar clicks, no spell went out. Errors: %s. Bar blocker: %s. Tell Claude this line.")
        :format(f.key, f.bar, #errs > 0 and table.concat(errs, ", ") or "none",
        (db and db.combatGuard == false) and "off" or (NS.GuardCurve() and (NS.guardFailed and "curve, failed" or "curve") or "none")))
end
function NS.FightCount(kind, msg)
    if not fight.key then return end
    if kind == "err" then msg = safe(msg); if type(msg) == "string" then fight.errs[msg] = (fight.errs[msg] or 0) + 1 end
    else fight[kind] = fight[kind] + 1 end
end
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_LEVEL_UP",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "GROUP_ROSTER_UPDATE",
    "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        TwizHealDB = TwizHealDB or {}
        db = TwizHealDB
        for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
        if (db.version or 0) < 3 then db.shown, db.clickCast, db.version = false, true, 3 end
        if db.version < 4 then db.shown, db.version = true, 4 end -- the party window is back: hover a bar + key
        if db.version < 5 then if db.threshold == 0.90 then db.threshold = 0.89 end; db.version = 5 end -- above 89%: no heal
        NS.db = db
        pcall(NS.HideNotReady)
        return
    end
    if not db then return end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then NS.SetBlockers(event == "PLAYER_REGEN_DISABLED") end
    if event == "PLAYER_REGEN_DISABLED" then NS.FightStart() elseif event == "PLAYER_REGEN_ENABLED" then NS.FightEnd() end
    if event == "PLAYER_REGEN_DISABLED" then return end
    -- moving / hovering / targeting: just re-run the rules so the key is right when you press it
    if event == "PLAYER_STARTED_MOVING" then NS.moving = true elseif event == "PLAYER_STOPPED_MOVING" then NS.moving = false end
    if event == "PLAYER_STARTED_MOVING" or event == "PLAYER_STOPPED_MOVING" or event == "UPDATE_MOUSEOVER_UNIT" or event == "PLAYER_TARGET_CHANGED" then
        if #ranks > 0 then NS.Update() end
        return
    end
    if event ~= "GROUP_ROSTER_UPDATE" and event ~= "PLAYER_REGEN_ENABLED" then
        local ok, err = pcall(NS.ReadRanks)
        if not ok then Print("couldn't read your spellbook: " .. tostring(err)) end
        if event == "PLAYER_ENTERING_WORLD" and #ranks > 0 and not db.told then
            db.told = true
            Print("works on the game's own party and raid frames: hover one and press your TwizHeal key (Options > Keybindings > AddOns > TwizHeal), or Alt+click it. Out of combat it picks Swiftmend / Regrowth / Rejuvenation / a small heal by how hurt they are; in combat it casts your fast heal. Bind the instant key (Rejuvenation, for moving) and the emergency key (Rejuvenation then Swiftmend) too. /th window shows TwizHeal's own bars.")
        end
    end
    NS.Update()
    if event ~= "ADDON_LOADED" then NS.ApplyClickCast() end
end)
local acc = 0
local tick = CreateFrame("Frame")
tick:SetScript("OnUpdate", function(_, e)
    acc = acc + e
    if acc < 0.2 then return end
    acc = 0
    -- spell text that wasn't loaded yet: look again a few times, then settle for the estimate
    if db and NS.needReread and not InCombatLockdown() and (NS.rereads or 0) < 5 and GetTime() - (NS.lastReread or 0) > 3 then
        NS.lastReread, NS.rereads = GetTime(), (NS.rereads or 0) + 1
        pcall(NS.ReadRanks)
    end
    if db and #ranks > 0 then NS.Update() end
end)

_G["BINDING_HEADER_TWIZHEAL"] = "TwizHeal"
_G["BINDING_NAME_CLICK TwizHealButton:LeftButton"] = "Heal whoever needs it most"
_G["BINDING_NAME_CLICK TwizHealButton:RightButton"] = "Instant heal (Rejuvenation / Renew) - use while moving"
_G["BINDING_NAME_CLICK TwizHealButton:MiddleButton"] = "Emergency: Rejuvenation, then Swiftmend or Regrowth (press twice)"
_G["BINDING_NAME_CLICK TwizHealButton:Button4"] = "Nature's Swiftness + Healing Touch (hover someone under 40%)"
_G["BINDING_NAME_CLICK TwizHealButton:Button5"] = "Tranquility (3+ under 40%; won't cut its own channel)"

SLASH_TWIZHEAL1 = "/th"
SLASH_TWIZHEAL2 = "/twizheal"
SlashCmdList.TWIZHEAL = function(msg)
    local cmd, rest = (msg or ""):lower():match("^(%S*)%s*(.-)$")
    local n = tonumber(rest)
    if cmd == "window" or cmd == "" then
        if InCombatLockdown() then Print("can't show or hide it in combat."); return end
        db.shown = not db.shown; NS.Update()
        Print("TwizHeal's own bars: " .. (db.shown and "shown" or "hidden (heal from the game's party/raid frames)"))
    elseif cmd == "clicks" then
        if InCombatLockdown() then Print("not in combat."); return end
        db.clickCast = not db.clickCast
        if db.clickCast then NS.ApplyClickCast() else
            for f in pairs(applied) do
                for _, k in ipairs({ "alt-type1", "alt-type2", "alt-ctrl-type1", "alt-ctrl-type2" }) do pcall(f.SetAttribute, f, k, nil) end
            end
        end
        Print("Alt+click healing on the game's party/raid frames: " .. (db.clickCast and "on" or "off"))
    elseif cmd == "danger" and n then
        db.danger = math.max(0.05, math.min(n / 100, 0.9)); Print(("anyone at %d%% or less is healed first, whatever their role"):format(db.danger * 100))
    elseif cmd == "threshold" and n then
        db.threshold = math.max(0.3, math.min(n / 100, 1)); Print(("people below %d%% are worth a heal"):format(db.threshold * 100))
    elseif cmd == "combatrank" then
        db.combatRank = n and math.floor(n) or nil
        local r = CombatDirect()
        Print(("Healing Touch in combat: %s"):format(r and ("rank " .. tostring(r.rank) .. (db.combatRank and "" or " (automatic: about 20% of the biggest health pool, below your top rank)")) or "?"))
        NS.Update()
    elseif cmd == "castinfo" then
        db.castInfo = db.castInfo == false
        Print("show which heal rank you cast: " .. (db.castInfo and "on" or "off"))
    elseif cmd == "quiet" then
        db.feedback = db.feedback == false
        Print("messages when a heal doesn't go out: " .. (db.feedback and "on" or "off"))
    elseif cmd == "test" then
        local m = TwizHealButton and TwizHealButton:GetAttribute("macrotext1") or "(none)"
        Print("the key runs:")
        for line in tostring(m):gmatch("[^\n]+") do Print("  " .. line) end
        local m2 = TwizHealButton and TwizHealButton:GetAttribute("macrotext2") or "(none)"
        Print("the instant-heal key runs:")
        for line in tostring(m2):gmatch("[^\n]+") do Print("  " .. line) end
        local m3 = TwizHealButton and TwizHealButton:GetAttribute("macrotext3") or "(none)"
        Print("the emergency key runs:")
        for line in tostring(m3):gmatch("[^\n]+") do Print("  " .. line) end
        Print(("out of combat the key picks: %s (%s)"):format(NS.ooc and NS.ooc.label or "-", tostring(NS.oocWhy)))
        Print(("it heals: %s; moving: %s"):format(Who(), tostring(Moving())))
    elseif cmd == "debug" then
        pcall(NS.ReadRanks)
        local hp = UnitHealth("player")
        Print(("heals found: %d; your health %s; window %s; in group: %s"):format(#ranks,
            safe(hp) and tostring(hp) or "HIDDEN by the game", frame and (frame:IsShown() and "shown" or "hidden") or "not built",
            tostring(IsInGroup and IsInGroup())))
        Print("combat 90% guard: " .. (NS.GuardCurve() and "whole bar (curve)" or "fallback - only the dark part of a bar under 90%"))
        reported = nil; NS.Update()
    elseif cmd == "guard" then
        db.combatGuard = db.combatGuard == false
        NS.SetBlockers(InCombatLockdown() and db.combatGuard)
        Print("in-combat bar blocker (no clicks on bars at 90%+): " .. (db.combatGuard and "on" or "off")
            .. (NS.GuardCurve() and "" or " - your game lacks the health curve it needs, so it stays off anyway"))
    elseif cmd == "prehot" then
        -- why each person does or doesn't get a pre-HoT
        for _, u in ipairs(Units()) do
            if UnitExists(u) then
                local hots, _, hid = MyHoTs(u)
                local hp = safe(UnitHealth(u)); local mx = safe(UnitHealthMax(u))
                local list = {}
                for n in pairs(hots) do list[#list + 1] = n end
                local r, why = OocRule(u)
                Print(("%s: health %s, your buffs %s, your HoTs on them: %s -> %s (%s)"):format(safe(UnitName(u)) or u,
                    (hp and mx and mx > 0) and (math.floor(hp / mx * 100 + 0.5) .. "%") or "HIDDEN",
                    hid and "HIDDEN" or "readable", #list > 0 and table.concat(list, ", ") or "none",
                    r and r.label or "nothing", tostring(why)))
            end
        end
        local p = NS.Pick(NS.Scan())
        Print("key goes to: " .. tostring(p and p.name or NS.fallback))
    elseif cmd == "ranks" then
        NS.ReadRanks()
        if #ranks == 0 then Print("no direct heals found in your spellbook.") end
        for _, r in ipairs(ranks) do
            print(("  %s [%s]: %s%s for %d mana"):format(r.label .. (r.rankText and r.rankText ~= "" and (" (" .. r.rankText .. ")") or ""), r.kind,
                r.avg > 0 and ("~%d"):format(r.avg) or "", r.hot > 0 and (" + %d over %ds"):format(r.hot, r.dur) or "", r.cost))
        end
    else
        Print("/th window - show/hide TwizHeal's own bars;  /th clicks - Alt+click healing on party/raid frames;  /th danger 30 - heal anyone at 30% or less first;  /th threshold 89 - nobody above this % gets healed;  /th ranks - your heals")
    end
end
