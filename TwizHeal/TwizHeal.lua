-- TwizHeal: one hotkey heals whoever needs it most, with the right-sized heal.
--
-- Who: you, your party (or raid). Among everyone missing enough health to be
-- worth a heal, tanks come first, then healers, then damage dealers; inside a
-- group, the lowest health goes first. Anyone in real danger (30% or less,
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

local DEFAULTS = { shown = true, danger = 0.30, threshold = 0.90, overheal = 1.10, clickCast = true }
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
    local hot, dur = text:match("(%d[%d,]*) damage over (%d+) sec")
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
                label = it.name, rankText = it.sub }
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
            if r.total * (db.overheal or 1.1) >= deficit then return r end
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
local function MyHoTs(unit)
    local out, incoming, hidden = {}, 0, false
    local _, class = UnitClass("player")
    local set = SPELLS[class] or {}
    local watch = { [set.hot or "-"] = true, [set.fast or "-"] = true }
    for i = 1, 40 do
        local a = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not a then break end
        local name, exp, src = safe(a.name), safe(a.expirationTime), safe(a.sourceUnit)
        if not name then hidden = true end
        if name and watch[name] and (src == "player" or safe(a.isFromPlayerOrPlayerPet)) then
            local left = exp and exp > 0 and (exp - GetTime()) or 0
            out[name] = math.max(0, left)
            -- the strongest rank you know of it, scaled by the time left
            for j = #ranks, 1, -1 do
                local r = ranks[j]
                if r.name == name and r.hot > 0 and r.dur > 0 then incoming = incoming + r.hot * math.min(1, left / r.dur); break end
            end
        end
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
                local hots, incoming = MyHoTs(u)
                -- what's still missing once your HoTs finish ticking
                local deficit = max - hp
                out[#out + 1] = { unit = u, name = safe(UnitName(u)) or u, hp = hp, max = max, pct = hp / max, deficit = deficit,
                    need = math.max(0, deficit - incoming), hots = hots, incoming = incoming,
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
            elseif m.need > 0 and ((m.pct <= (db.threshold or 0.9) and m.need >= smallest * 0.5) or m.need >= smallest) then
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
    table.sort(need, function(a, b)
        local ra, rb = ROLE_RANK[a.role] or 3, ROLE_RANK[b.role] or 3
        if ra ~= rb then return ra < rb end
        return a.pct < b.pct
    end)
    if need[1] then return need[1], false end
    table.sort(upkeep, function(a, b) return a.pct < b.pct end)
    return upkeep[1], false
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
local function Moving()
    local s = GetUnitSpeed and safe(GetUnitSpeed("player"))
    return (s and s > 0) or (IsFalling and IsFalling() and true) or false
end
NS.Moving = Moving

local function OocRule(unit)
    local hot, fast = Best("hot"), Best("fast")
    if Moving() then
        if hot then return hot, "moving" end
    end
    local hots, hidden = {}, true
    if unit and UnitExists(unit) then
        local h, _, hid = MyHoTs(unit)
        hots, hidden = h, hid
    end
    local cur, mx = safe(UnitHealth(unit or "player")), safe(UnitHealthMax(unit or "player"))
    local pct = cur and mx and mx > 0 and cur / mx or nil
    local need = pct and (mx - cur) or nil
    if pct and pct < 0.5 then
        if fast and not hidden and not hots[fast.name] then return PickRank(need, "fast") or fast, "low" end
        return PickRank(need, "direct") or Best("direct"), "low"
    end
    if hot and not hidden and not hots[hot.name] then return (need and need > 0 and PickRank(need, "hot")) or hot, "topping off" end
    return (need and need > 0 and PickRank(need, "direct")) or Best("direct", 2) or Best("direct") or hot, "topping off"
end
NS.OocRule = OocRule

local function Chain(c, unit, only)
    if only then return ("[%s@%s]"):format(c, unit) end
    return ("[%s@mouseover,help,nodead][%s@target,help,nodead][%s@%s]"):format(c, c, c, unit)
end
-- ooc = the spell the rules picked for out of combat (nil = do nothing out of combat)
-- only = heal exactly that unit (TwizHeal's own bars)
local function SmartMacro(unit, ooc, only)
    local fast, hot = Best("fast"), Best("hot")
    local combat = fast or Best("direct", 1) or Best("direct")
    local _, class = UnitClass("player")
    local lines = {}
    -- druids: drop cat/bear/travel form first (heals can't be cast in them)
    if class == "DRUID" then lines[#lines + 1] = "/cancelform [form]" end
    if ooc then lines[#lines + 1] = "/cast " .. Chain("nocombat,", unit, only) .. " " .. ooc.label end
    if combat then lines[#lines + 1] = "/cast " .. Chain("combat,", unit, only) .. " " .. combat.label end
    if hot and combat and combat ~= hot then lines[#lines + 1] = "/cast " .. Chain("combat,", unit, only) .. " " .. hot.label end
    return table.concat(lines, "\n")
end
NS.SmartMacro = SmartMacro

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
        b.incBar:SetStatusBarColor(0.55, 1, 0.55, 0.55)
        b.incBar:SetMinMaxValues(0, 1); b.incBar:SetValue(0)
        local fill = b.bar:GetStatusBarTexture()
        b.incBar:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0); b.incBar:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
        b.incBar:SetWidth(198)
        b.inc = b.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.inc:SetPoint("RIGHT", b.pct, "LEFT", -4, 0)
        b.inc:SetTextColor(0.55, 1, 0.55)
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
        -- mana (always, even in cat/bear form) and energy/rage under the health bar
        for _, k in ipairs({ "mana", "power" }) do
            local pb = CreateFrame("StatusBar", nil, b)
            pb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            pb:SetMinMaxValues(0, 1); pb:SetValue(0)
            pb.bg = pb:CreateTexture(nil, "BACKGROUND"); pb.bg:SetAllPoints(); pb.bg:SetColorTexture(0.05, 0.05, 0.07, 1)
            b[k] = pb
        end
        b.mana:SetStatusBarColor(0.0, 0.44, 0.87)
        b:Hide()
        bars[i] = b
    end

    btn = CreateFrame("Button", "TwizHealButton", frame, "SecureActionButtonTemplate")
    btn:SetSize(1, 1); btn:SetPoint("BOTTOMLEFT"); btn:SetAlpha(0)
    btn:RegisterForClicks("AnyUp", "AnyDown") -- acts once, on press or release per the "cast on key down" option
    btn:SetAttribute("type", "macro")
    -- tell you when a press didn't heal (out of range, can't cast while moving...)
    btn:HookScript("PostClick", function() if NS.OnPress then NS.OnPress() end end)
    for _, b in ipairs(bars) do
        if b.SetFrameRef then b:SetFrameRef("key", btn) end
        b:SetAttribute("_onenter", [[
            local key = self:GetFrameRef("key")
            local m = self:GetAttribute("healmacro")
            if key and m then key:SetAttribute("macrotext", m) end
        ]])
        b:SetAttribute("_onleave", [[
            local key = self:GetFrameRef("key")
            if key then key:SetAttribute("macrotext", key:GetAttribute("basemacro")) end
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
        b.powerH = ph
        b.laid = nil -- power bars re-anchor on the next update
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
        local a = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL")
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
    if UnitIsDeadOrGhost(unit) then b.pct:SetText(""); return end
    local cur, mx = UnitHealth(unit), UnitHealthMax(unit)
    local c, m = safe(cur), safe(mx)
    if c and m and m > 0 then
        b.pct:SetText(("%d / %d  %d%%"):format(c, m, c / m * 100 + 0.5))
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
        local a = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
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

local function HealthColor(pct)
    if pct < 0.35 then return 1, 0.4, 0.4 elseif pct < 0.7 then return 1, 0.69, 0.4 end
    return 0.56, 0.88, 0.56
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
            b.bar:SetStatusBarColor(HealthColor(pct))
            pcall(DrawPower, b, unit)
            local dead = UnitIsDeadOrGhost(unit)
            b.name:SetText(("%s%s"):format(safe(UnitName(unit)) or unit, dead and " |cff9aa1abdead|r" or ""))
            pcall(NS.SetRoleIcon, b.role, Role(unit))
            pcall(NS.DrawStatus, b, unit)
            pcall(NS.DrawHPText, b, unit)
            pcall(NS.DrawAbsorb, b, unit)
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
    -- who the key heals: your mouseover, else a friendly target, else the pick (or the tank when health is hidden)
    local fallback = pick and pick.unit
    if not fallback then
        fallback = "player"
        if NS.hidden then for _, u in ipairs(Units()) do if u ~= "player" and Role(u) == "TANK" then fallback = u; break end end end
    end
    local function friend(u) return UnitExists(u) and not UnitIsDeadOrGhost(u) and (not UnitCanAssist or UnitCanAssist("player", u)) end
    local who = (NS.hoverUnit and UnitExists(NS.hoverUnit) and NS.hoverUnit) or friend("mouseover") and "mouseover" or friend("target") and "target" or fallback
    local ooc, why
    ooc, why = OocRule(who)
    if inCombat then
        local fast, hot = Best("fast") or Best("direct", 1), Best("hot")
        frame.next:SetText(fast and ("|cfff0c45c%s|r%s"):format(fast.name, hot and (" |cff9aa1ab(moving: " .. hot.name .. ")|r") or "") or "no heal known")
    elseif ooc then
        frame.next:SetText(("%s%s|r -> %s |cff9aa1ab(%s)|r"):format(why == "low" and "|cffff8060" or "|cfff0c45c", ooc.label,
            UnitIsUnit and UnitIsUnit(who, "player") and "you" or (safe(UnitName(who)) or who), why))
    else
        frame.next:SetText(NS.hidden and "|cff9aa1abhealth hidden - hover the lowest bar|r" or "|cff8fe08feveryone's fine|r")
    end
    NS.ooc, NS.oocWhy = ooc, why
    if not inCombat then NS.fallback = fallback end
    if not inCombat then
        local base = SmartMacro(fallback, ooc)
        btn:SetAttribute("basemacro", base)
        local hovered
        -- each bar keeps its own heal: clicking it, or hovering it and pressing the key, uses that
        for _, b in ipairs(bars) do
            local unit = b:GetAttribute("unit")
            if UnitExists(unit) then
                local r, w = OocRule(unit)
                local m = SmartMacro(unit, r, true)
                SetMacro(b, m)
                if b:GetAttribute("healmacro") ~= m then b:SetAttribute("healmacro", m) end
                if NS.hoverUnit == unit then hovered = m end
            end
        end
        SetMacro(btn, hovered or base)
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
local function Who()
    local function friend(u) return UnitExists(u) and not UnitIsDeadOrGhost(u) and (not UnitCanAssist or UnitCanAssist("player", u)) end
    local u = NS.hoverUnit and UnitExists(NS.hoverUnit) and NS.hoverUnit or friend("mouseover") and "mouseover" or friend("target") and "target" or NS.fallback or "player"
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
    if GetTime() - press.at > 0.6 or press.said then return end
    if event == "UI_ERROR_MESSAGE" then
        local msg = safe(type(a2) == "string" and a2 or a1)
        if type(msg) == "string" and msg ~= "" and not press.err then press.err = msg end
    elseif a1 == "player" then
        if event == "UNIT_SPELLCAST_FAILED" then press.failed = true else press.done = true end
    end
end)
local fbTick = CreateFrame("Frame")
fbTick:SetScript("OnUpdate", function()
    if press.at == 0 or press.said or GetTime() - press.at < 0.6 then return end
    press.said = true
    if press.done or (db and db.feedback == false) then return end
    local who = press.who or "?"
    if press.err then
        Print(("couldn't heal %s: %s"):format(who, press.err))
    elseif press.failed then
        Print(("the heal on %s failed (range, line of sight or mana?)"):format(who))
    else
        Print(("key pressed but nothing was cast on %s - %s"):format(who,
            #ranks == 0 and "no heals found (/th ranks)" or "/th test shows what the key does"))
    end
end)

------------------------------------------------------------------------
-- Events, slash
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_LEVEL_UP",
    "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE",
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
        NS.db = db
        return
    end
    if not db then return end
    -- moving / hovering / targeting: just re-run the rules so the key is right when you press it
    if event == "PLAYER_STARTED_MOVING" or event == "PLAYER_STOPPED_MOVING" or event == "UPDATE_MOUSEOVER_UNIT" or event == "PLAYER_TARGET_CHANGED" then
        if #ranks > 0 then NS.Update() end
        return
    end
    if event ~= "GROUP_ROSTER_UPDATE" and event ~= "PLAYER_REGEN_ENABLED" then
        local ok, err = pcall(NS.ReadRanks)
        if not ok then Print("couldn't read your spellbook: " .. tostring(err)) end
        if event == "PLAYER_ENTERING_WORLD" and #ranks > 0 and not db.told then
            db.told = true
            Print("works on the game's own party and raid frames: hover one and press your TwizHeal key (Options > Keybindings > AddOns > TwizHeal), or Alt+click it. Out of combat it picks Rejuvenation/Regrowth/a small heal by rules (moving, topping off); in combat it casts your fast heal, or your HoT while moving. /th window shows TwizHeal's own bars.")
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
_G["BINDING_NAME_CLICK TwizHealButton:RightButton"] = "Heal whoever needs it most (same, second key)"

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
    elseif cmd == "quiet" then
        db.feedback = db.feedback == false
        Print("messages when a heal doesn't go out: " .. (db.feedback and "on" or "off"))
    elseif cmd == "test" then
        local m = TwizHealButton and TwizHealButton:GetAttribute("macrotext") or "(none)"
        Print("the key runs:")
        for line in tostring(m):gmatch("[^\n]+") do Print("  " .. line) end
        Print(("it heals: %s; moving: %s"):format(Who(), tostring(Moving())))
    elseif cmd == "debug" then
        pcall(NS.ReadRanks)
        local hp = UnitHealth("player")
        Print(("heals found: %d; your health %s; window %s; in group: %s"):format(#ranks,
            safe(hp) and tostring(hp) or "HIDDEN by the game", frame and (frame:IsShown() and "shown" or "hidden") or "not built",
            tostring(IsInGroup and IsInGroup())))
        reported = nil; NS.Update()
    elseif cmd == "ranks" then
        NS.ReadRanks()
        if #ranks == 0 then Print("no direct heals found in your spellbook.") end
        for _, r in ipairs(ranks) do
            print(("  %s [%s]: %s%s for %d mana"):format(r.label .. (r.rankText and r.rankText ~= "" and (" (" .. r.rankText .. ")") or ""), r.kind,
                r.avg > 0 and ("~%d"):format(r.avg) or "", r.hot > 0 and (" + %d over %ds"):format(r.hot, r.dur) or "", r.cost))
        end
    else
        Print("/th window - show/hide TwizHeal's own bars;  /th clicks - Alt+click healing on party/raid frames;  /th danger 30 - heal anyone at 30% or less first;  /th threshold 90 - who's worth a heal;  /th ranks - your heals")
    end
end
