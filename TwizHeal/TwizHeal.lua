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
                label = (it.sub and it.sub ~= "") and ("%s(%s)"):format(it.name, it.sub) or it.name }
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
    local out, incoming = {}, 0
    local _, class = UnitClass("player")
    local set = SPELLS[class] or {}
    local watch = { [set.hot or "-"] = true, [set.fast or "-"] = true }
    for i = 1, 40 do
        local a = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not a then break end
        local name, exp, src = safe(a.name), safe(a.expirationTime), safe(a.sourceUnit)
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
    return out, incoming
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
local MOD_TEXT = { hot = "ctrl", fast = "shift", direct = "" }

------------------------------------------------------------------------
-- The hotkey button and party bars
------------------------------------------------------------------------
local frame, btn, bars = nil, nil, {}
local MAXBARS = 5

-- plain = the smart choice (out of combat) / main heal (in combat); shift = fast heal; ctrl = HoT.
-- In combat: your mouseover (a party bar), else a friendly target, else the last pick.
local function MacroFor(unit, spellLabel, fastLabel, hotLabel)
    local f = fastLabel or spellLabel
    local h = hotLabel or spellLabel
    local function part(mod, label)
        return ("[%s@mouseover,help,nodead,combat][%scombat,@target,help,nodead][%s@%s] %s"):format(mod, mod, mod, unit, label)
    end
    return "/cast " .. part("mod:ctrl,", h) .. "; " .. part("mod:shift,", f) .. "; " .. part("", spellLabel)
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
        b:RegisterForClicks("AnyUp", "AnyDown")
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
    btn:RegisterForClicks("AnyUp", "AnyDown") -- acts once, on press or release per the "cast on key down" option
    btn:SetAttribute("type", "macro")
    frame:Hide() -- shown by the first successful update
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
            b.bar:SetStatusBarColor(HealthColor(pct))
            local dead = UnitIsDeadOrGhost(unit)
            b.name:SetText(("%s |cff9aa1ab%s|r"):format(safe(UnitName(unit)) or unit, m and ROLE_TEXT[m.role] or (dead and "dead" or "")))
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
    -- HoT timers on the bars
    for _, b in ipairs(bars) do
        local m = byUnit[b:GetAttribute("unit")]
        local tags = {}
        for name, left in pairs(m and m.hots or {}) do tags[#tags + 1] = ("%s %d"):format(name:sub(1, 5), left) end
        if #tags > 0 then b.pct:SetText(("|cff8fe08f%s|r  %s"):format(table.concat(tags, " "), b.pct:GetText() or "")) end
    end
    if pick then
        local r, kind = NS.Choose(pick, emergency)
        local mod = MOD_TEXT[kind or "direct"]
        frame.next:SetText(r and ("%s%s|r%s -> %s"):format(emergency and "|cffff8060" or "|cfff0c45c", r.label,
            mod ~= "" and (" |cff9aa1ab(" .. mod .. ")|r") or "", pick.unit == "player" and "you" or pick.name) or "no heal known")
        if not inCombat and r then
            local fast = PickRank(pick.need, "fast")
            local hot = Has("hot") and PickRank(pick.need, "hot")
            btn:SetAttribute("macrotext", MacroFor(pick.unit, r.label, fast and fast.label, hot and hot.label))
            -- clicking a bar heals that person: the rank for a typical deficit (40% of their health)
            for _, b in ipairs(bars) do
                local unit = b:GetAttribute("unit")
                local m = byUnit[unit]
                if m then
                    local typical = math.max(m.need, m.max * 0.4)
                    local rr = PickRank(typical, "direct")
                    local ff = PickRank(m.max * 0.4, "fast")
                    local hh = Has("hot") and PickRank(m.max * 0.2, "hot")
                    if rr then
                        b:SetAttribute("macrotext", ("/cast [mod:ctrl,@%s] %s; [mod:shift,@%s] %s; [@%s] %s"):format(
                            unit, (hh or rr).label, unit, (ff or rr).label, unit, rr.label))
                    end
                end
            end
        end
    else
        frame.next:SetText(NS.hidden and "|cff9aa1abhealth hidden by the game|r" or "|cff8fe08feveryone's fine|r")
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
        local ok, err = pcall(NS.ReadRanks)
        if not ok then Print("couldn't read your spellbook: " .. tostring(err)) end
        if event == "PLAYER_ENTERING_WORLD" and #ranks > 0 and not db.told then
            db.told = true
            Print("bind a key in Options > Keybindings > AddOns > TwizHeal. Out of combat it heals whoever needs it most with the smartest spell; in combat hover a TwizHeal bar (the gold one is the pick) and press it - plain = main heal, Shift = fast heal, Ctrl = HoT. The window shows which one to use.")
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
    if cmd == "" then
        if InCombatLockdown() then Print("can't show or hide it in combat."); return end
        db.shown = not db.shown; NS.Update()
    elseif cmd == "danger" and n then
        db.danger = math.max(0.05, math.min(n / 100, 0.9)); Print(("anyone at %d%% or less is healed first, whatever their role"):format(db.danger * 100))
    elseif cmd == "threshold" and n then
        db.threshold = math.max(0.3, math.min(n / 100, 1)); Print(("people below %d%% are worth a heal"):format(db.threshold * 100))
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
            print(("  %s [%s]: %s%s for %d mana"):format(r.label, r.kind,
                r.avg > 0 and ("~%d"):format(r.avg) or "", r.hot > 0 and (" + %d over %ds"):format(r.hot, r.dur) or "", r.cost))
        end
    else
        Print("/th - show/hide;  /th danger 30 - heal anyone at 30% or less first;  /th threshold 90 - who's worth a heal;  /th ranks - your heals")
    end
end
