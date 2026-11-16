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

local DEFAULTS = { shown = true, wheel = true, shadowProt = false, thorns = true, hideWhenDone = true, minGroup = 3, strangers = true, skipPvP = false }

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

local function Auras(unit)
    local have = {}
    for i = 1, 40 do
        local name
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
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
    btn:RegisterForClicks("AnyDown")
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
    local list = NS.Missing()
    local nextCast = NS.NextCast(list)
    local inCombat = InCombatLockdown()
    for i = 1, ROWS do
        local m = list[i]
        if m then
            local who = m.unit == "player" and "you" or ClassColor(m.classFile, m.name or m.unit)
            rows[i]:SetText(("%s%s  |cff9aa1ab->|r %s%s"):format(m.inRange and "" or "|cff7c838d", m.spell, who,
                m.inRange and "" or "  (out of range)|r"))
            rows[i]:Show()
        else
            rows[i]:Hide()
        end
    end
    frame.count:SetText(#list > 0 and ("%d missing"):format(#list) or "all buffed")
    -- One key for buffing and healing: with TwizHeal loaded, the same key heals whoever
    -- needs it most - in combat always, and out of combat when someone is hurt; otherwise it
    -- casts the next missing buff (out of combat only).
    local heal = TwizHealButton and TwizHeal and TwizHeal.pick
    if not inCombat then
        local lines = {}
        if TwizHealButton then lines[#lines + 1] = "/click [combat] TwizHealButton" end
        if heal then
            lines[#lines + 1] = "/click [nocombat] TwizHealButton"
            btn.label:SetText("Heal " .. (heal.unit == "player" and "you" or (heal.name or heal.unit)))
            btn:SetAlpha(1)
        elseif nextCast then
            lines[#lines + 1] = ("/cast [nocombat,@%s] %s"):format(nextCast.unit, nextCast.spell)
            btn.label:SetText("Cast " .. nextCast.label)
            btn:SetAlpha(1)
        else
            btn.label:SetText(#list > 0 and "Nobody in range" or "Everyone has your buffs")
            btn:SetAlpha(0.5)
        end
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("macrotext", table.concat(lines, "\n"))
        local shown = math.min(#list, ROWS)
        frame:SetHeight(28 + shown * 15 + 42)
        local want = db.shown and (#list > 0 or not db.hideWhenDone)
        frame:SetShown(want and true or false)
        SetWheel(db.wheel and (nextCast ~= nil or heal ~= nil))
    else
        btn.label:SetText(TwizHealButton and "In combat: heals" or "In combat")
    end
    NS.next = nextCast
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
        Print("/tb - show/hide;  /tb wheel on|off - cast with the mouse wheel;  /tb strangers on|off - nearby players too;  /tb pvp - skip PvP-flagged strangers;  /tb auto - hide when all buffed;  /tb shadow, /tb thorns - include those;  /tb group N - group version at N people")
    end
end
