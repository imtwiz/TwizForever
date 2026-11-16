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

local DEFAULTS = { shown = true, danger = 0.30, threshold = 0.90, overheal = 1.10 }
local SPELLS = {
    PRIEST  = { direct = { "Lesser Heal", "Heal", "Greater Heal" }, fast = "Flash Heal" },
    DRUID   = { direct = { "Healing Touch" }, fast = "Regrowth" },
    PALADIN = { direct = { "Holy Light" }, fast = "Flash of Light" },
    SHAMAN  = { direct = { "Healing Wave" }, fast = "Lesser Healing Wave" },
}
local ROLE_RANK = { TANK = 1, HEALER = 2, DAMAGER = 3 }
local ROLE_TEXT = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }

local db
local function Print(m) print("|cff8fe08fTwizHeal|r: " .. tostring(m)) end

------------------------------------------------------------------------
-- Your heal ranks: { name, rank, label = "Heal(Rank 3)", avg, cost, fast }
------------------------------------------------------------------------
local ranks = {}

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

local function HealAmount(id)
    local text = (C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(id))
        or (GetSpellDescription and GetSpellDescription(id)) or ""
    local lo, hi = text:match("(%d[%d,]*) to (%d[%d,]*)")
    if lo then
        lo, hi = tonumber((lo:gsub(",", ""))), tonumber((hi:gsub(",", "")))
        return (lo + hi) / 2
    end
end

local function Cost(id)
    local costs = C_Spell and C_Spell.GetSpellPowerCost and C_Spell.GetSpellPowerCost(id)
        or (GetSpellPowerCost and GetSpellPowerCost(id))
    local c = costs and costs[1]
    return c and (c.cost or c.minCost) or 0
end

function NS.ReadRanks()
    wipe(ranks)
    local _, class = UnitClass("player")
    local set = SPELLS[class]
    if not set then return end
    local want = {}
    for _, n in ipairs(set.direct) do want[n] = false end
    want[set.fast] = true
    for _, it in ipairs(SpellBookItems()) do
        local isFast = want[it.name]
        if isFast ~= nil then
            local r = tonumber((it.sub or ""):match("(%d+)")) or 1
            local avg = HealAmount(it.id)
            if avg then
                ranks[#ranks + 1] = { name = it.name, rank = r, avg = avg, cost = Cost(it.id), fast = isFast,
                    label = (it.sub and it.sub ~= "") and ("%s(%s)"):format(it.name, it.sub) or it.name }
            end
        end
    end
    table.sort(ranks, function(a, b) return a.avg < b.avg end)
end
NS.ranks = ranks

-- smallest heal that covers the deficit (within the overheal allowance) and that you can afford
local function PickRank(deficit, fast)
    local mana = UnitPower("player", 0) or 0
    local best
    for _, r in ipairs(ranks) do
        if r.fast == (fast and true or false) and r.cost <= mana then
            best = r
            if r.avg * (db.overheal or 1.1) >= deficit then return r end
        end
    end
    if best then return best end
    if fast then return PickRank(deficit, false) end
end
NS.PickRank = PickRank

------------------------------------------------------------------------
-- Who needs it
------------------------------------------------------------------------
local function Role(unit)
    local r = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if r == "TANK" or r == "HEALER" or r == "DAMAGER" then return r end
    -- whoever enemies are attacking is tanking
    local threat = UnitThreatSituation and UnitThreatSituation(unit)
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
        if checked then return inRange end
    end
    if spell and C_Spell and C_Spell.IsSpellInRange then
        local r = C_Spell.IsSpellInRange(spell, unit)
        if r ~= nil then return r == true or r == 1 end
    end
    return UnitIsVisible and UnitIsVisible(unit) or true
end

-- everyone, with health and role: { unit, name, hp, max, pct, deficit, role, inRange }
function NS.Scan()
    local out = {}
    for _, u in ipairs(Units()) do
        if UnitIsConnected(u) and not UnitIsDeadOrGhost(u) then
            local hp, max = UnitHealth(u) or 0, UnitHealthMax(u) or 1
            if max > 0 then
                out[#out + 1] = { unit = u, name = UnitName(u), hp = hp, max = max, pct = hp / max, deficit = max - hp,
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
    local smallest = ranks[1] and ranks[1].avg or 1
    local danger, need = {}, {}
    for _, m in ipairs(list) do
        if m.inRange and m.deficit > 0 then
            if m.pct <= (db.danger or 0.3) then danger[#danger + 1] = m
            elseif m.pct <= (db.threshold or 0.9) or m.deficit >= smallest then need[#need + 1] = m end
        end
    end
    table.sort(danger, function(a, b) return a.pct < b.pct end)
    if danger[1] then return danger[1], true end
    table.sort(need, function(a, b)
        local ra, rb = ROLE_RANK[a.role] or 3, ROLE_RANK[b.role] or 3
        if ra ~= rb then return ra < rb end
        return a.pct < b.pct
    end)
    return need[1], false
end

------------------------------------------------------------------------
-- The hotkey button and party bars
------------------------------------------------------------------------
local frame, btn, bars = nil, nil, {}
local MAXBARS = 5

local function MacroFor(unit, spellLabel, fastLabel)
    -- in combat: mouseover (a party bar), else a friendly target, else the last pick
    local s = spellLabel
    local f = fastLabel or spellLabel
    return ("/cast [mod:shift,@mouseover,help,nodead][mod:shift,combat,@target,help,nodead][mod:shift,@%s] %s; [@mouseover,help,nodead,combat][combat,@target,help,nodead][@%s] %s")
        :format(unit, f, unit, s)
end

local function Build()
    local Skin = NS.Skin
    frame = CreateFrame("Frame", "TwizHealFrame", UIParent, "BackdropTemplate")
    frame:SetSize(220, 40 + MAXBARS * 22)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -260)
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton"); frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", frame.StartMoving)
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

    -- party bars: secure unit buttons, so hovering one is your "mouseover" and clicking it heals
    for i = 1, MAXBARS do
        local b = CreateFrame("Button", "TwizHealBar" .. i, frame, "SecureUnitButtonTemplate,BackdropTemplate")
        b:SetSize(200, 20)
        b:SetPoint("TOPLEFT", 10, -30 - (i - 1) * 22)
        b:RegisterForClicks("AnyDown")
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
        b.name = b.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.name:SetPoint("LEFT", 4, 0)
        b.pct = b.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.pct:SetPoint("RIGHT", -4, 0)
        b:Hide()
        bars[i] = b
    end

    btn = CreateFrame("Button", "TwizHealButton", frame, "SecureActionButtonTemplate")
    btn:SetSize(1, 1); btn:SetPoint("BOTTOMLEFT"); btn:SetAlpha(0)
    btn:RegisterForClicks("AnyDown")
    btn:SetAttribute("type", "macro")
end

local function HealthColor(pct)
    if pct < 0.35 then return 1, 0.4, 0.4 elseif pct < 0.7 then return 1, 0.69, 0.4 end
    return 0.56, 0.88, 0.56
end

function NS.Update()
    if not db then return end
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
            local pct = m and m.pct or 0
            b.bar:SetValue(pct)
            b.bar:SetStatusBarColor(HealthColor(pct))
            b.name:SetText(("%s |cff9aa1ab%s|r"):format(UnitName(unit) or unit, m and ROLE_TEXT[m.role] or "dead"))
            b.pct:SetText(m and ("%d%%"):format(pct * 100 + 0.5) or "")
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
    if pick then
        local r = PickRank(pick.deficit, emergency)
        local big = PickRank(pick.deficit, false)
        frame.next:SetText(r and ("%s%s|r -> %s"):format(emergency and "|cffff8060" or "|cfff0c45c", r.label, pick.unit == "player" and "you" or pick.name) or "no heal known")
        if not inCombat and r then
            local fast = PickRank(pick.deficit, true)
            btn:SetAttribute("macrotext", MacroFor(pick.unit, r.label, fast and fast.label))
            -- clicking a bar heals that person: the rank for a typical deficit (40% of their health)
            for _, b in ipairs(bars) do
                local unit = b:GetAttribute("unit")
                local m = byUnit[unit]
                local rr = m and PickRank(math.max(m.deficit, m.max * 0.4), false) or big
                local ff = m and PickRank(m.max * 0.4, true)
                if rr then
                    b:SetAttribute("macrotext", ("/cast [mod:shift,@%s] %s; [@%s] %s"):format(unit, (ff or rr).label, unit, rr.label))
                end
            end
        end
    else
        frame.next:SetText("|cff8fe08feveryone's fine|r")
        if not inCombat then
            -- nobody needs healing: in combat the hotkey still heals your mouseover/target with a mid heal
            local mid = ranks[math.max(1, math.ceil(#ranks / 2))]
            if mid then btn:SetAttribute("macrotext", MacroFor("player", mid.label)) end
        end
    end
    if not inCombat then
        frame:SetHeight(36 + math.max(1, shown) * 22)
        frame:SetShown(db.shown and #ranks > 0)
    end
    NS.pick = pick
end

------------------------------------------------------------------------
-- Events, slash
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_LEVEL_UP",
    "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        TwizHealDB = TwizHealDB or {}
        db = TwizHealDB
        for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
        NS.db = db
        return
    end
    if not db then return end
    if event ~= "GROUP_ROSTER_UPDATE" and event ~= "PLAYER_REGEN_ENABLED" then
        NS.ReadRanks()
        if event == "PLAYER_ENTERING_WORLD" and #ranks > 0 and not db.told then
            db.told = true
            Print("bind a key in Options > Keybindings > AddOns > TwizHeal. Out of combat it heals whoever needs it most; in combat hover a TwizHeal bar (the gold one is the pick) and press it. Shift = fast heal.")
        end
    end
    NS.Update()
end)
local acc = 0
local tick = CreateFrame("Frame")
tick:SetScript("OnUpdate", function(_, e)
    acc = acc + e
    if acc < 0.2 then return end
    acc = 0
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
    if cmd == "" then
        if InCombatLockdown() then Print("can't show or hide it in combat."); return end
        db.shown = not db.shown; NS.Update()
    elseif cmd == "danger" and n then
        db.danger = math.max(0.05, math.min(n / 100, 0.9)); Print(("anyone at %d%% or less is healed first, whatever their role"):format(db.danger * 100))
    elseif cmd == "threshold" and n then
        db.threshold = math.max(0.3, math.min(n / 100, 1)); Print(("people below %d%% are worth a heal"):format(db.threshold * 100))
    elseif cmd == "ranks" then
        NS.ReadRanks()
        if #ranks == 0 then Print("no direct heals found in your spellbook.") end
        for _, r in ipairs(ranks) do print(("  %s%s: heals ~%d for %d mana"):format(r.label, r.fast and " (fast)" or "", r.avg, r.cost)) end
    else
        Print("/th - show/hide;  /th danger 30 - heal anyone at 30% or less first;  /th threshold 90 - who's worth a heal;  /th ranks - your heals")
    end
end
