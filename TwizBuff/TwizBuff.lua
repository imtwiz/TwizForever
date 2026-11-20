-- TwizBuff: which friendly players are missing the buffs your class can give,
-- and a button that casts the next one.
--
-- Who: you, your party or raid, and your target when it's a friendly player.
-- What: Mark of the Wild, Power Word: Fortitude, Divine Spirit, Arcane
-- Intellect, a Blessing, Battle Shout... only spells you actually know. When
-- three or more people in your group need the same buff and you have the
-- group version (and its reagent), it casts that instead.
--
-- The game needs a click, key press or mouse-wheel notch for every cast, and
-- the cast button can only be re-aimed out of combat. Bind a key in
-- Options > Keybindings > AddOns > TwizBuff, or /tb wheel on to cast with the
-- mouse wheel while something is missing (out of combat).
local ADDON, NS = ...
TwizBuff = NS

local DEFAULTS = { shown = true, wheel = true, shadowProt = false, thorns = true, hideWhenDone = true, minGroup = 3, strangers = true, skipPvP = false, nearest = false }

-- names: what to cast; also = auras that already count (group versions, greater blessings)
-- mana = only for people who use mana; group = group version (needs a reagent)
local BUFFS = {
    DRUID = {
        { key = "motw", spell = "Mark of the Wild", group = "Gift of the Wild", also = { "Gift of the Wild" } },
        { key = "thorns", spell = "Thorns", opt = "thorns" },   -- on by default (/tb thorns to leave it out)
    },
    PRIEST = {
        { key = "fort", spell = "Power Word: Fortitude", group = "Prayer of Fortitude", also = { "Prayer of Fortitude" } },
        { key = "spirit", spell = "Divine Spirit", group = "Prayer of Spirit", also = { "Prayer of Spirit" }, mana = true },
        { key = "shadow", spell = "Shadow Protection", group = "Prayer of Shadow Protection", also = { "Prayer of Shadow Protection" }, opt = "shadowProt" },
    },
    MAGE = {
        { key = "int", spell = "Arcane Intellect", group = "Arcane Brilliance", also = { "Arcane Brilliance" }, mana = true },
    },
    PALADIN = {
        { key = "blessing", blessing = true },
    },
    WARRIOR = {
        { key = "shout", spell = "Battle Shout", selfOnly = true },
    },
}
-- what each class can remove, best spell first (Abolish keeps cleansing over time)
local DISPELS = {
    DRUID   = { Curse = { "Remove Curse" }, Poison = { "Abolish Poison", "Cure Poison" } },
    PRIEST  = { Magic = { "Dispel Magic" }, Disease = { "Abolish Disease", "Cure Disease" } },
    MAGE    = { Curse = { "Remove Lesser Curse", "Remove Curse" } },
    PALADIN = { Magic = { "Cleanse" }, Poison = { "Cleanse", "Purify" }, Disease = { "Cleanse", "Purify" } },
    SHAMAN  = { Poison = { "Cure Poison" }, Disease = { "Cure Disease" } },
}
local ABOLISH = { Poison = "Abolish Poison", Disease = "Abolish Disease" }
local DISPEL_ORDER = { Curse = 1, Poison = 2, Disease = 3, Magic = 4 }
local DISPEL_HEX = { Curse = "a330c9", Poison = "00cc33", Disease = "c2853b", Magic = "3399ff" }
local BLESSINGS = { "Blessing of Kings", "Blessing of Wisdom", "Blessing of Might", "Blessing of Salvation", "Blessing of Light", "Blessing of Sanctuary" }

local db
local function Print(m) print("|cff8fe08fTwizBuff|r: " .. tostring(m)) end

------------------------------------------------------------------------
-- Spells and auras
------------------------------------------------------------------------
local function Known(name)
    if not name then return false end
    local id
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(name)
        id = info and info.spellID
    elseif GetSpellInfo then
        id = select(7, GetSpellInfo(name))
    end
    if not id then return false end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return false
end

local function Usable(name)
    if C_Spell and C_Spell.IsSpellUsable then
        local ok = C_Spell.IsSpellUsable(name)
        return ok and true or false
    end
    if IsUsableSpell then return IsUsableSpell(name) and true or false end
    return true
end

local function InRange(name, unit)
    if unit == "player" then return true end
    local r
    if C_Spell and C_Spell.IsSpellInRange then r = C_Spell.IsSpellInRange(name, unit)
    elseif IsSpellInRange then r = IsSpellInRange(name, unit) end
    if r == nil then return UnitIsVisible and UnitIsVisible(unit) or false end
    return r == true or r == 1
end

-- aura reads: in combat this client can refuse them outright ("cannot be accessed when secret"),
-- which is an error, not a hidden value - treat it as "can't see auras right now"
local function AuraAt(unit, i, filter)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
    if ok then return a end
    return nil, true -- blocked
end

local function Auras(unit)
    local have = {}
    for i = 1, 40 do
        local name
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = AuraAt(unit, i, "HELPFUL")
            name = a and a.name
        elseif UnitBuff then
            name = UnitBuff(unit, i)
        end
        if not name then break end
        have[name] = true
    end
    return have
end

local function UsesMana(unit)
    local t = UnitPowerType and UnitPowerType(unit)
    return t == 0 or (Enum and Enum.PowerType and t == Enum.PowerType.Mana)
end

-- which blessing to give someone: Kings if you have it, Wisdom for mana users, Might otherwise
local function BlessingFor(unit)
    if Known("Blessing of Kings") then return "Blessing of Kings" end
    if UsesMana(unit) and Known("Blessing of Wisdom") then return "Blessing of Wisdom" end
    if Known("Blessing of Might") then return "Blessing of Might" end
    if Known("Blessing of Wisdom") then return "Blessing of Wisdom" end
end
local function HasBlessing(have)
    for _, b in ipairs(BLESSINGS) do
        if have[b] or have["Greater " .. b] then return true end
    end
    return false
end

------------------------------------------------------------------------
-- Who needs what
------------------------------------------------------------------------
local function Units()
    local list, seen = { "player" }, {}
    seen[UnitGUID("player") or "player"] = true
    local function add(u)
        if not UnitExists(u) then return end
        local g = UnitGUID(u) or u
        if seen[g] then return end
        seen[g] = true
        list[#list + 1] = u
    end
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do add("raid" .. i) end
    else
        for i = 1, 4 do add("party" .. i) end
    end
    -- strangers: your target, whoever is under your mouse, and every friendly player with a
    -- nameplate (friendly nameplates show who's near you)
    local function stranger(u)
        if not UnitExists(u) or not UnitIsPlayer(u) or not UnitIsFriend("player", u) then return end
        if UnitIsUnit and UnitIsUnit(u, "player") then return end
        -- buffing someone flagged for PvP flags you too: /tb pvp skips them unless you already are
        if db.skipPvP and UnitIsPVP and UnitIsPVP(u) and not UnitIsPVP("player") then return end
        add(u)
    end
    stranger("target")
    if db.strangers then
        stranger("mouseover")
        for i = 1, 40 do stranger("nameplate" .. i) end
    end
    return list
end

local function GroupUnit(u) return u == "player" or u:match("^party%d") or u:match("^raid%d") end

local function plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end

-- debuffs you can remove: { { unit, name, spell, kind, debuff, inRange }, ... }, most urgent first
function NS.Debuffed()
    local _, class = UnitClass("player")
    local can = DISPELS[class]
    local out = {}
    if not can or (db and db.dispel == false) then return out end
    local spellFor = {}
    for kind, list in pairs(can) do
        for _, sp in ipairs(list) do if Known(sp) then spellFor[kind] = sp; break end end
    end
    if not next(spellFor) then return out end
    for _, u in ipairs(Units()) do
        if UnitIsConnected(u) and not UnitIsDeadOrGhost(u) and (not UnitCanAssist or UnitCanAssist("player", u)) then
            local have = Auras(u)
            local seen = {}
            for i = 1, 40 do
                local a = AuraAt(u, i, "HARMFUL")
                if not a then break end
                local kind = plain(a.dispelName)
                local sp = kind and spellFor[kind]
                -- Abolish Poison/Disease already on them is clearing it
                if sp and not seen[kind] and not (ABOLISH[kind] and have[ABOLISH[kind]] and sp == ABOLISH[kind]) then
                    seen[kind] = true
                    out[#out + 1] = { unit = u, name = UnitName(u), spell = sp, kind = kind, debuff = plain(a.name) or kind,
                        inRange = InRange(sp, u), classFile = select(2, UnitClass(u)) }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.inRange ~= b.inRange then return a.inRange end
        local function rank(u) return u == "player" and 1 or (GroupUnit(u) and 2) or 3 end
        local pa, pb = rank(a.unit), rank(b.unit)
        if pa ~= pb then return pa < pb end
        return DISPEL_ORDER[a.kind] < DISPEL_ORDER[b.kind]
    end)
    return out
end

-- { { unit, name, spell, buff, inRange }, ... } in casting order
function NS.Missing()
    local _, class = UnitClass("player")
    local defs = BUFFS[class] or {}
    local out = {}
    for _, u in ipairs(Units()) do
        if UnitIsConnected(u) and not UnitIsDeadOrGhost(u) then
            local have = Auras(u)
            for bi, b in ipairs(defs) do
                if not b.opt or db[b.opt] then
                    local spell, missing
                    if b.blessing then
                        spell = BlessingFor(u)
                        missing = spell and not HasBlessing(have)
                    elseif b.selfOnly then
                        spell = b.spell
                        missing = u == "player" and Known(spell) and not have[spell]
                    else
                        spell = b.spell
                        missing = Known(spell) and not have[spell]
                        for _, a in ipairs(b.also or {}) do if have[a] then missing = false end end
                        if missing and b.mana and not UsesMana(u) then missing = false end
                    end
                    if missing then
                        out[#out + 1] = { unit = u, name = UnitName(u), spell = spell, buff = b, order = bi, inRange = InRange(spell, u),
                            classFile = select(2, UnitClass(u)) }
                    end
                end
            end
        end
    end
    -- the target first, then you, then everyone in range before those out of range
    table.sort(out, function(a, b)
        if a.inRange ~= b.inRange then return a.inRange end
        local function rank(u) return u == "target" and 0 or (u == "player" and 1) or (GroupUnit(u) and 2) or 3 end
        local pa, pb = rank(a.unit), rank(b.unit)
        if pa ~= pb then return pa < pb end
        if a.unit ~= b.unit then return a.unit < b.unit end
        return a.order < b.order
    end)
    return out
end

-- Downranking: the game won't put a buff on someone more than 10 levels below the rank's level
-- ("target is too low level"). For a low-level target, cast the highest rank they can take.
-- Ranks come from your spellbook (or the known rank IDs), levels from the game or the rank table.
-- Casting a lower rank needs its spell ID ("/cast Spell(Rank 3)" doesn't work on this client),
-- so it goes through a small secure spell button that the key /clicks.
local RANK_LEVELS = {
    ["Mark of the Wild"]      = { 1, 10, 20, 30, 40, 50, 60 },
    ["Thorns"]                = { 6, 14, 24, 34, 44, 54 },
    ["Power Word: Fortitude"] = { 1, 12, 24, 36, 48, 60 },
    ["Arcane Intellect"]      = { 1, 14, 28, 42, 56 },
    ["Divine Spirit"]         = { 30, 40, 50, 60 },
    ["Shadow Protection"]     = { 30, 42, 56 },
}
local RANK_IDS = {
    ["Mark of the Wild"] = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 },
    ["Thorns"] = { 467, 782, 1075, 8914, 9756, 9910 },
    ["Power Word: Fortitude"] = { 1243, 1244, 1245, 2791, 10937, 10938 },
    ["Arcane Intellect"] = { 1459, 1460, 1461, 10156, 10157 },
}
local rankCache = {}
function NS.Ranks(spell)
    if rankCache[spell] then return rankCache[spell] end
    local out, byId = {}, {}
    local function add(id, rank)
        if not id or byId[id] then return end
        local known = (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id))
        if not known then return end
        local lvl = GetSpellLevelLearned and plain(GetSpellLevelLearned(id))
        if type(lvl) ~= "number" or lvl <= 0 then lvl = RANK_LEVELS[spell] and RANK_LEVELS[spell][rank or 0] end
        byId[id] = true
        out[#out + 1] = { id = id, rank = rank, level = lvl or 1 }
    end
    -- spellbook entries named like the buff
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if info then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    if item and item.name == spell and item.spellID then
                        add(item.spellID, tonumber(tostring(item.subName or ""):match("(%d+)")))
                    end
                end
            end
        end
    end
    for r, id in ipairs(RANK_IDS[spell] or {}) do add(id, r) end
    table.sort(out, function(a, b) return a.level < b.level end)
    rankCache[spell] = out
    return out
end
function NS.ClearRanks() for k in pairs(rankCache) do rankCache[k] = nil end end

-- the rank to use on unit: nil = your best rank (cast by name as usual)
function NS.RankFor(spell, unit)
    local ranks = NS.Ranks(spell)
    if #ranks < 2 then return nil end
    local tl = plain(UnitLevel(unit))
    if type(tl) ~= "number" or tl <= 0 then return nil end
    local pick
    for _, r in ipairs(ranks) do if r.level <= tl + 10 then pick = r end end
    pick = pick or ranks[1]
    if pick == ranks[#ranks] then return nil end
    return pick
end

local castButtons = {}
local function CastButton(n)
    if castButtons[n] then return castButtons[n] end
    local b = CreateFrame("Button", "TwizBuffCast" .. n, UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "spell")
    b:Hide()
    castButtons[n] = b
    return b
end
-- the macro line that casts spell on unit, downranked if they're too low for your best rank
function NS.CastLine(spell, unit, n)
    local r = NS.RankFor(spell, unit)
    if not r then return ("/cast [nocombat,@%s,help,nodead] %s"):format(unit, spell), nil end
    local b = CastButton(n or 1)
    b:SetAttribute("spell", r.id)
    b:SetAttribute("unit", unit)
    local keyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    return "/click [nocombat] TwizBuffCast" .. (n or 1) .. (keyDown and " LeftButton 1" or ""), r
end

-- Nearest friend: the closest friendly player who's missing your main buff (Mark of the Wild,
-- Fortitude, Arcane Intellect...). Closeness: exact yards for group members when the game
-- gives positions, else 10 yd / 28 yd / spell-range rings (CheckInteractDistance).
local function Yards(u)
    if UnitIsUnit and UnitIsUnit(u, "player") then return 0 end
    if UnitPosition then
        local ok, x1, y1, _, i1 = pcall(UnitPosition, "player")
        local ok2, x2, y2, _, i2 = pcall(UnitPosition, u)
        if ok and ok2 then
            x1, y1, x2, y2 = plain(x1), plain(y1), plain(x2), plain(y2)
            if x1 and x2 and y1 and y2 and i1 == i2 then return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) end
        end
    end
    if CheckInteractDistance and not InCombatLockdown() then
        local ok, near = pcall(CheckInteractDistance, u, 3)
        if ok and near then return 9 end
        ok, near = pcall(CheckInteractDistance, u, 4)
        if ok and near then return 27 end
    end
    return 35
end
NS.Yards = Yards
function NS.NearestTarget(list)
    local _, class = UnitClass("player")
    local main = BUFFS[class] and BUFFS[class][1]
    local spell = main and not main.blessing and not main.selfOnly and main.spell
    if not spell or not Known(spell) then return nil end
    local best, bestD, seen = nil, math.huge, {}
    for _, m in ipairs(list or NS.Missing()) do
        local key = m.name or m.unit
        if m.spell == spell and m.inRange and not seen[key] then
            seen[key] = true
            local d = Yards(m.unit)
            if d < bestD then best, bestD = m, d end
        end
    end
    if best then best.yards = bestD end
    return best
end

-- the toggle: while on, the TwizBuff key (and wheel) buffs the nearest friend missing your
-- main buff instead of the usual next-missing-buff order (debuff removal still comes first)
function TwizBuff_ToggleNearest()
    if not db then return end
    db.nearest = not db.nearest
    local main = (BUFFS[select(2, UnitClass("player"))] or {})[1]
    Print("nearest-friend " .. tostring(main and main.spell or "buff") .. ": " ..
        (db.nearest and "|cff8fe08fON|r - your TwizBuff key buffs the closest friend missing it" or "|cffff8060OFF|r"))
    if NS.Update then NS.Update() end
end

-- the next cast: a group version when enough group members need the same buff
function NS.NextCast(list)
    list = list or NS.Missing()
    local count = {}
    for _, m in ipairs(list) do
        if m.buff.group and GroupUnit(m.unit) and m.inRange then count[m.buff.key] = (count[m.buff.key] or 0) + 1 end
    end
    -- one group cast beats several single ones
    for _, m in ipairs(list) do
        local b = m.buff
        if m.inRange and b.group and GroupUnit(m.unit) and (count[b.key] or 0) >= (db.minGroup or 3) and Known(b.group) and Usable(b.group) then
            return { spell = b.group, unit = m.unit, label = ("%s (%d people)"):format(b.group, count[b.key]) }
        end
    end
    for _, m in ipairs(list) do
        if m.inRange then
            if Usable(m.spell) then
                return { spell = m.spell, unit = m.unit, label = ("%s on %s"):format(m.spell, m.unit == "player" and "you" or (m.name or m.unit)) }
            end
        end
    end
end

------------------------------------------------------------------------
-- Window and the secure cast button
------------------------------------------------------------------------
local frame, btn, rows = nil, nil, {}
local ROWS = 8
local CLASS_HEX = {}
local function ClassColor(cf, s)
    local c = cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
    if c then return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, s) end
    return s
end

local function Build()
    local Skin = NS.Skin
    frame = CreateFrame("Frame", "TwizBuffFrame", UIParent, "BackdropTemplate")
    frame:SetSize(250, 60)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 260, -200)
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton"); frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        db.pos = { p, rp, x, y }
    end)
    if db.pos then frame:ClearAllPoints(); frame:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4]) end
    Skin.Panel(frame)
    frame.title = Skin.Text(frame, "title"); frame.title:SetPoint("TOPLEFT", 10, -9); frame.title:SetText("TwizBuff")
    frame.count = Skin.Text(frame, "muted"); frame.count:SetPoint("LEFT", frame.title, "RIGHT", 8, 0)
    local close = Skin.IconButton(frame, "x", "Hide (/tb to show)", function() db.shown = false; frame:Hide() end)
    close:SetPoint("TOPRIGHT", -6, -5)
    for i = 1, ROWS do
        local r = Skin.Text(frame, "small")
        r:SetPoint("TOPLEFT", 12, -28 - (i - 1) * 15); r:SetPoint("RIGHT", -12, 0)
        rows[i] = r
    end

    -- secure: only its attributes decide what gets cast (set out of combat)
    btn = CreateFrame("Button", "TwizBuffButton", frame, "SecureActionButtonTemplate,BackdropTemplate")
    btn:SetHeight(26)
    btn:SetPoint("BOTTOMLEFT", 8, 8); btn:SetPoint("BOTTOMRIGHT", -8, 8)
    btn:RegisterForClicks("AnyUp", "AnyDown") -- acts once, on press or release per the "cast on key down" option
    btn:SetAttribute("type", "spell")
    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.label:SetPoint("CENTER")
    if btn.SetBackdrop then
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        btn:SetBackdropColor(0.941, 0.769, 0.361, 1); btn:SetBackdropBorderColor(1, 0.835, 0.455, 1)
    end
    btn.label:SetTextColor(0.102, 0.078, 0.031)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("TwizBuff", 0.94, 0.77, 0.36)
        GameTooltip:AddLine("Casts the next missing buff. Bind a key in Options > Keybindings > AddOns > TwizBuff, or /tb wheel on to use the mouse wheel.", 1, 1, 1, true)
        local r = NS.near
        GameTooltip:AddLine("Right-click: " .. (r and (r.spell .. " on the nearest friend missing it - " .. tostring(r.name or r.unit)) or "nearest friend - nobody in range is missing your buff"), 0.5, 0.8, 1, true)
        GameTooltip:AddLine("Nearest-friend mode (/tb nearest or its key): " .. (db and db.nearest and "ON" or "off"), 0.5, 0.8, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:HookScript("PostClick", function() C_Timer.After(0.3, NS.Update) end)
end

local wheelOwner = CreateFrame("Frame")
local wheelBound = false
local function SetWheel(on)
    if on == wheelBound or InCombatLockdown() then return end
    if on then
        SetOverrideBindingClick(wheelOwner, false, "MOUSEWHEELUP", "TwizBuffButton", "LeftButton")
        SetOverrideBindingClick(wheelOwner, false, "MOUSEWHEELDOWN", "TwizBuffButton", "LeftButton")
    else
        ClearOverrideBindings(wheelOwner)
    end
    wheelBound = on
end

function NS.Update()
    if not db then return end
    if not frame then Build() end
    -- in combat the key can't change and the game may refuse aura reads: wait for the fight to end
    if InCombatLockdown() and frame.built then return end
    frame.built = true
    local list = NS.Missing()
    local nextCast = NS.NextCast(list)
    local inCombat = InCombatLockdown()
    -- debuffs come first: in the list and on the key
    local debuffs = NS.Debuffed()
    local cleanse
    for _, d in ipairs(debuffs) do if d.inRange and Usable(d.spell) then cleanse = d; break end end
    local nd = math.min(#debuffs, ROWS)
    for i = 1, nd do
        local d = debuffs[i]
        local who = d.unit == "player" and "you" or ClassColor(d.classFile, d.name or d.unit)
        rows[i]:SetText(("|cff%s%s|r  |cff9aa1ab->|r %s |cff9aa1ab(%s)|r%s"):format(DISPEL_HEX[d.kind] or "ffffff", d.spell, who,
            tostring(d.debuff), d.inRange and "" or "  |cff7c838d(out of range)|r"))
        rows[i]:Show()
    end
    for i = nd + 1, ROWS do
        local m = list[i - nd]
        if m then
            local who = m.unit == "player" and "you" or ClassColor(m.classFile, m.name or m.unit)
            rows[i]:SetText(("%s%s  |cff9aa1ab->|r %s%s"):format(m.inRange and "" or "|cff7c838d", m.spell, who,
                m.inRange and "" or "  (out of range)|r"))
            rows[i]:Show()
        else
            rows[i]:Hide()
        end
    end
    frame.count:SetText((#debuffs > 0 and ("|cffff8060%d to cleanse|r  "):format(#debuffs) or "") .. (#list > 0 and ("%d missing"):format(#list) or "all buffed"))
    -- One key for buffing and healing: with TwizHeal loaded, the same key heals whoever
    -- needs it most - in combat always, and out of combat when someone is hurt; otherwise it
    -- casts the next missing buff (out of combat only).
    local heal = TwizHealButton and TwizHeal and TwizHeal.pick
    local near = NS.NearestTarget(list)
    NS.near = near
    if not inCombat then
        local lines = {}
        -- /click must match the "cast on key down" option, or the heal button ignores it
        local keyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
        local target = "TwizHealButton" .. (keyDown and " LeftButton 1" or "")
        if TwizHealButton then lines[#lines + 1] = "/click [combat] " .. target end
        if cleanse then
            -- a debuff you can remove beats a heal or a buff
            lines[#lines + 1] = ("/cast [nocombat,@%s] %s"):format(cleanse.unit, cleanse.spell)
            btn.label:SetText(("%s %s"):format(cleanse.spell, cleanse.unit == "player" and "you" or (cleanse.name or cleanse.unit)))
            btn:SetAlpha(1)
        elseif db.nearest and near then
            -- toggle on: the closest friend missing your main buff
            local line, r = NS.CastLine(near.spell, near.unit, 1)
            lines[#lines + 1] = line
            btn.label:SetText(("%s%s %s"):format(near.spell, r and (" (rank " .. (r.rank or "?") .. ")") or "", near.unit == "player" and "you" or (near.name or near.unit)))
            btn:SetAlpha(1)
        elseif heal then
            lines[#lines + 1] = "/click [nocombat] " .. target
            btn.label:SetText("Heal " .. (heal.unit == "player" and "you" or (heal.name or heal.unit)))
            btn:SetAlpha(1)
        elseif nextCast then
            local line, r = NS.CastLine(nextCast.spell, nextCast.unit, 1)
            lines[#lines + 1] = line
            btn.label:SetText("Cast " .. nextCast.label .. (r and (" (rank " .. (r.rank or "?") .. ")") or ""))
            btn:SetAlpha(1)
        else
            btn.label:SetText(#list > 0 and "Nobody in range" or "Everyone has your buffs")
            btn:SetAlpha(0.5)
        end
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("macrotext", table.concat(lines, "\n"))
        -- right button / "Nearest friend" key: your main buff on the closest friend missing it
        local r = near
        local m2 = r and (NS.CastLine(r.spell, r.unit, 2)) or ""
        if btn:GetAttribute("macrotext2") ~= m2 then btn:SetAttribute("macrotext2", m2) end
        local shown = math.min(#list + #debuffs, ROWS)
        frame:SetHeight(28 + shown * 15 + 42)
        local want = db.shown and (#list > 0 or #debuffs > 0 or not db.hideWhenDone)
        frame:SetShown(want and true or false)
        SetWheel(db.wheel and (nextCast ~= nil or heal ~= nil or cleanse ~= nil))
    else
        btn.label:SetText(TwizHealButton and "In combat: heals" or "In combat")
    end
    NS.next, NS.cleanse = nextCast, cleanse
end

------------------------------------------------------------------------
-- Events, slash command
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "UNIT_AURA", "PLAYER_TARGET_CHANGED",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "SPELLS_CHANGED", "UNIT_CONNECTION", "PLAYER_LEVEL_UP", "BAG_UPDATE_DELAYED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local pending
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "SPELLS_CHANGED" and NS.ClearRanks then NS.ClearRanks() end -- learned a new rank
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        TwizBuffDB = TwizBuffDB or {}
        db = TwizBuffDB
        for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
        -- 1.2: Thorns and the mouse wheel are on by default now
        if (db.version or 0) < 2 then db.thorns, db.wheel, db.version = true, true, 2 end
        NS.db = db
        return
    end
    if event == "PLAYER_ENTERING_WORLD" and db.strangers and not db.platesSet and not InCombatLockdown() and GetCVar and SetCVar then
        db.platesWas = GetCVar("nameplateShowFriends")
        if db.platesWas ~= "1" then
            SetCVar("nameplateShowFriends", "1")
            Print("turned on friendly nameplates so I can see nearby players who need buffs. /tb strangers off puts them back.")
        end
        db.platesSet = true
    end
    if event == "PLAYER_ENTERING_WORLD" and not db.toldWheel then
        db.toldWheel = true
        Print("spin your mouse wheel (out of combat) to buff whoever is missing your buffs - each notch casts one. The game needs a notch, click or key press per cast; /tb wheel off gives the wheel back to the camera.")
    end
    if not db then return end
    if event == "PLAYER_REGEN_DISABLED" then SetWheel(false) end
    if pending then return end
    pending = true
    C_Timer.After(0.25, function() pending = false; NS.Update() end)
end)
-- range changes as people move
C_Timer.NewTicker(1, function() if db and frame and (frame:IsShown() or db.shown) then NS.Update() end end)

_G["BINDING_HEADER_TWIZBUFF"] = "TwizBuff"
_G["BINDING_NAME_CLICK TwizBuffButton:LeftButton"] = "Buff / heal: next missing buff out of combat; with TwizHeal, heals whoever needs it most"
_G["BINDING_NAME_CLICK TwizBuffButton:RightButton"] = "Nearest friend missing it: Mark of the Wild (your main buff)"
_G["BINDING_NAME_TWIZBUFF_NEAREST"] = "Toggle nearest-friend mode (the TwizBuff key buffs the closest friend)"

SLASH_TWIZBUFF1 = "/tb"
SLASH_TWIZBUFF2 = "/twizbuff"
SlashCmdList.TWIZBUFF = function(msg)
    local cmd, rest = (msg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "" then
        db.shown = not (frame and frame:IsShown())
        if db.shown then db.hideWhenDone = false end
        NS.Update()
    elseif cmd == "wheel" then
        db.wheel = rest == "on" or (rest == "" and not db.wheel)
        Print("mouse wheel casts the next buff (out of combat, while something's missing): " .. (db.wheel and "on" or "off"))
        NS.Update()
    elseif cmd == "auto" then
        db.hideWhenDone = not db.hideWhenDone
        Print("hide the window when everyone is buffed: " .. (db.hideWhenDone and "on" or "off"))
        NS.Update()
    elseif cmd == "shadow" or cmd == "thorns" then
        local k = cmd == "shadow" and "shadowProt" or "thorns"
        db[k] = not db[k]
        Print((cmd == "shadow" and "Shadow Protection" or "Thorns") .. ": " .. (db[k] and "included" or "left out"))
        NS.Update()
    elseif cmd == "nearest" then
        TwizBuff_ToggleNearest()
    elseif cmd == "cleanse" then
        db.dispel = db.dispel == false
        Print("remove curses / poisons / diseases / magic with the same key: " .. (db.dispel and "on" or "off"))
        NS.Update()
    elseif cmd == "strangers" then
        db.strangers = rest == "on" or (rest == "" and not db.strangers)
        if not InCombatLockdown() and SetCVar then
            if db.strangers then
                db.platesWas = db.platesWas or GetCVar("nameplateShowFriends"); SetCVar("nameplateShowFriends", "1"); db.platesSet = true
            elseif db.platesWas then
                SetCVar("nameplateShowFriends", db.platesWas); db.platesSet = nil
            end
        end
        Print("buff nearby strangers (friendly players with nameplates or under your mouse): " .. (db.strangers and "on" or "off"))
        NS.Update()
    elseif cmd == "pvp" then
        db.skipPvP = not db.skipPvP
        Print("PvP-flagged strangers: " .. (db.skipPvP and "skipped unless you're flagged (buffing them would flag you)" or "buffed like anyone else"))
        NS.Update()
    elseif cmd == "group" and tonumber(rest) then
        db.minGroup = math.max(2, math.min(tonumber(rest), 40))
        Print(("group buff when %d or more need it"):format(db.minGroup))
    else
        Print("/tb - show/hide;  /tb wheel on|off - cast with the mouse wheel;  /tb strangers on|off - nearby players too;  /tb pvp - skip PvP-flagged strangers;  /tb auto - hide when all buffed;  /tb shadow, /tb thorns - include those;  /tb cleanse - remove debuffs with the key on/off;  /tb nearest - nearest-friend mode on/off;  /tb group N - group version at N people")
    end
end
