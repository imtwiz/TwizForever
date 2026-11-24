-- TwizInterrupt: interrupts for every class.
--   Interrupt key (Options > Keybindings > AddOns > TwizInterrupt): your class's interrupt on the
--   enemy under your mouse, else your target - Kick, Pummel / Shield Bash, Counterspell, Wind Shear /
--   Earth Shock, Silence, Spell Lock (felhunter), Rebuke / Hammer of Justice, Bash / Feral Charge
--   (Bear Form), Scatter Shot / Intimidation / Silencing Shot, War Stomp / Arcane Torrent... If the
--   first one is on cooldown the next one goes off.
--   Alert: the moment your target - or, in a fight, an enemy near you - starts casting something
--   you can interrupt, a big INTERRUPT alert shows who is casting what, whether your interrupt is
--   ready and in range, and which key to press (with a warning sound).
--   Attack keys (1.1.0): in a fight, the TwizRogue / TwizWarrior / TwizHunt attack keys also fire
--   your interrupt on the target whenever it's ready, so you don't need a second key.
-- The game only lets a key press cast a spell, and a macro can't see whether the enemy is casting,
-- so the attack key fires the interrupt as soon as it's off cooldown; /interrupt attack turns that off.
local ADDON, NS = ...
local db
local DEFAULTS = { alert = true, sound = true, nearby = true, hover = true, locked = true, attackKeys = true }

local function Print(m) DEFAULT_CHAT_FRAME:AddMessage("|cffff7f3fTwizInterrupt|r: " .. tostring(m)) end
local function plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end
local function secret(v) return issecretvalue and issecretvalue(v) or false end

local function SpellID(name)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        return ok and info and info.spellID or nil
    elseif GetSpellInfo then
        return select(7, GetSpellInfo(name))
    end
end

local function Known(name, pet)
    local id = name and SpellID(name)
    if not id then return false end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and (IsSpellKnown(id) or (pet and IsSpellKnown(id, true))) then return true end
    return false
end
NS.Known = Known

-- { spell, extra macro conditions, pet spell, not on the attack key }; first known one that's ready
-- goes off. Crowd control that breaks on damage is kept off the attack keys.
NS.SPELLS = {
    WARRIOR = { { "Pummel", "stance:3" }, { "Shield Bash", "equipped:Shields,nostance:3" } },
    ROGUE = { { "Kick" }, { "Gouge", nil, nil, true } },
    MAGE = { { "Counterspell" } },
    SHAMAN = { { "Wind Shear" }, { "Earth Shock" } },
    PRIEST = { { "Silence" } },
    WARLOCK = { { "Spell Lock", nil, true } },
    PALADIN = { { "Rebuke" }, { "Hammer of Justice" } },
    HUNTER = { { "Counter Shot" }, { "Silencing Shot" }, { "Scatter Shot", nil, nil, true }, { "Intimidation" } },
    DRUID = { { "Skull Bash", "form:1/3" }, { "Bash", "form:1" }, { "Feral Charge - Bear", "form:1" }, { "Feral Charge", "form:1" } },
    DEATHKNIGHT = { { "Mind Freeze" } },
}
NS.RACIALS = { { "War Stomp" }, { "Arcane Torrent" } }

-- the interrupts this character has right now
function NS.List()
    local out = {}
    local class = select(2, UnitClass("player"))
    local function add(e)
        local ok = Known(e[1], e[3])
        if not ok and e[3] and class == "WARLOCK" and UnitCreatureFamily and plain(UnitCreatureFamily("pet")) == "Felhunter" then ok = true end
        if ok then out[#out + 1] = e end
    end
    for _, e in ipairs(NS.SPELLS[class] or {}) do add(e) end
    for _, e in ipairs(NS.RACIALS) do add(e) end
    return out
end

local AttackLinesCount
local function Cond(unit, extra) return ("@%s,harm,nodead%s"):format(unit, extra and ("," .. extra) or "") end

function NS.Macro()
    local lines = {}
    for _, e in ipairs(NS.List()) do
        if db.hover then
            lines[#lines + 1] = ("/cast [%s][%s] %s"):format(Cond("mouseover", e[2]), Cond("target", e[2]), e[1])
        else
            lines[#lines + 1] = ("/cast [%s] %s"):format(Cond("target", e[2]), e[1])
        end
    end
    return table.concat(lines, "\n")
end

AttackLinesCount = function()
    local n = 0
    for _, e in ipairs(NS.List()) do if not e[4] then n = n + 1 end end
    return n
end

-- lines the class addons put at the top of their attack keys (empty when turned off)
function NS.AttackLines()
    if not db or not db.attackKeys then return "" end
    local lines = {}
    for _, e in ipairs(NS.List()) do
        if not e[4] then lines[#lines + 1] = ("/cast [combat,%s] %s"):format(Cond("target", e[2]), e[1]) end
    end
    if #lines == 0 then return "" end
    return table.concat(lines, "\n") .. "\n"
end

local function UpdateClassKeys()
    for _, name in ipairs({ "TwizRogue", "TwizWarrior", "TwizHunt" }) do
        local a = _G[name]
        if type(a) == "table" and a.Update then pcall(a.Update) end
    end
end

local btn = CreateFrame("Button", "TwizInterruptButton", UIParent, "SecureActionButtonTemplate")
btn:RegisterForClicks("AnyUp", "AnyDown")
btn:SetAttribute("type", "macro")
btn:Hide()

function NS.Update()
    if not db or InCombatLockdown() then return end
    local m = NS.Macro()
    if btn:GetAttribute("macrotext1") ~= m then btn:SetAttribute("macrotext1", m) end
end

-- ---------------------------------------------------------------- what would go off right now
local function CooldownLeft(spell)
    local start, dur
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, cd = pcall(C_Spell.GetSpellCooldown, spell)
        if ok and cd then start, dur = cd.startTime, cd.duration end
    elseif GetSpellCooldown then
        start, dur = GetSpellCooldown(spell)
    end
    start, dur = plain(start), plain(dur)
    if not start or not dur then return nil end -- unknown (hidden in combat): treat as ready
    if dur <= 1.5 then return 0 end              -- just the global cooldown
    return math.max(0, start + dur - GetTime())
end

local function InRange(spell, unit)
    local r
    if C_Spell and C_Spell.IsSpellInRange then
        local ok, v = pcall(C_Spell.IsSpellInRange, spell, unit); if ok then r = v end
    elseif IsSpellInRange then
        local ok, v = pcall(IsSpellInRange, spell, unit); if ok then r = v end
    end
    r = plain(r)
    if r == nil then return nil end
    return r == true or r == 1
end

-- the interrupt that would go off on unit: spell, seconds of cooldown left (0 = ready, nil = unknown)
function NS.Pick(unit)
    local first, firstLeft
    for _, e in ipairs(NS.List()) do
        local applies = true
        if e[2] and SecureCmdOptionParse then applies = SecureCmdOptionParse("[" .. e[2] .. "] x") == "x" end
        if applies then
            local left = CooldownLeft(e[1])
            if not left or left == 0 then return e[1], left end
            if not first then first, firstLeft = e[1], left end
        end
    end
    return first, firstLeft
end

local ATTACK = { ROGUE = { "TwizRogueButton:LeftButton" }, WARRIOR = { "TwizWarriorButton:LeftButton" },
    HUNTER = { "TwizHuntButton:LeftButton", "TwizHuntButton:RightButton" } }
local function KeyText()
    if not GetBindingKey then return nil end
    if db and db.attackKeys and AttackLinesCount and AttackLinesCount() > 0 then
        for _, b in ipairs(ATTACK[select(2, UnitClass("player"))] or {}) do
            local k = _G[b:match("^[^:]+")] and GetBindingKey("CLICK " .. b)
            if k then return (GetBindingText and GetBindingText(k) or k) .. " (attack key)" end
        end
    end
    local key = GetBindingKey and (GetBindingKey("CLICK TwizInterruptButton:LeftButton")
        or GetBindingKey("CLICK TwizRogueButton:RightButton") or GetBindingKey("CLICK TwizWarriorButton:MiddleButton"))
    if not key then return nil end
    return GetBindingText and GetBindingText(key) or key
end
NS.KeyText = KeyText

-- ---------------------------------------------------------------- watching casts
local casts = {} -- unit token -> { at = GetTime(), stop = GetTime() deadline }
NS.casts = casts

local function Hostile(unit)
    if not UnitExists or not plain(UnitExists(unit)) then return false end
    local ok, v = pcall(UnitCanAttack, "player", unit)
    if not ok then return false end
    if secret(v) then return true end
    return v and true or false
end

local function CastInfo(unit)
    local name, _, _, _, endMS, _, _, noKick = UnitCastingInfo(unit)
    if secret(name) or name then return name, endMS, noKick end
    local cname, _, _, _, cend, _, cnoKick = UnitChannelInfo(unit)
    if secret(cname) or cname then return cname, cend, cnoKick end
end

local function Watching(unit)
    if unit == "target" or unit == "focus" then return true end
    if db.nearby and unit:match("^nameplate%d+$") then
        if UnitIsUnit and plain(UnitIsUnit(unit, "target")) then return false end -- the target line has it
        local fighting = plain(UnitAffectingCombat("player")) or plain(UnitIsUnit(unit .. "target", "player"))
        return fighting and true or false
    end
    return false
end

local Refresh
local function Start(unit)
    if not db or not db.alert or not Watching(unit) or not Hostile(unit) then return end
    local name, endMS, noKick = CastInfo(unit)
    if not secret(name) and not name then return end
    if plain(noKick) == true then casts[unit] = nil; Refresh(); return end
    local now = GetTime()
    endMS = plain(endMS)
    casts[unit] = { at = now, stop = endMS and (endMS / 1000 + 0.2) or (now + 10), name = name }
    Refresh(true)
end
local function Stop(unit) if casts[unit] then casts[unit] = nil; Refresh() end end

-- ---------------------------------------------------------------- the alert
local f = CreateFrame("Frame", "TwizInterruptAlert", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
f:SetSize(300, 64)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 170)
f:SetFrameStrata("HIGH")
f:SetClampedToScreen(true)
if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.15, 0, 0, 0.8)
end
f.icon = f:CreateTexture(nil, "ARTWORK")
f.icon:SetSize(48, 48)
f.icon:SetPoint("LEFT", 8, 0)
f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, 0)
f.who = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
f.who:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
f.dash = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
f.dash:SetPoint("LEFT", f.who, "RIGHT", 4, 0)
f.dash:SetText("-")
f.what = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
f.what:SetPoint("LEFT", f.dash, "RIGHT", 4, 0)
f.how = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
f.how:SetPoint("TOPLEFT", f.who, "BOTTOMLEFT", 0, -2)
f:Hide()
f:SetMovable(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", function(s) if not db.locked then s:StartMoving() end end)
f:SetScript("OnDragStop", function(s)
    s:StopMovingOrSizing()
    local x, y = s:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if x and ux then db.x, db.y = x - ux, y - uy end
end)
NS.frame = f

local function Place()
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or 170)
    f:EnableMouse(not db.locked)
end

local function SafeText(fs, v, fallback)
    if v == nil then fs:SetText(fallback); return end
    if not pcall(fs.SetText, fs, v) then fs:SetText(fallback) end
end

local function Pick()
    if casts.target then return "target" end
    if casts.focus then return "focus" end
    local best
    for unit, c in pairs(casts) do
        local spell = NS.Pick(unit)
        local r = spell and InRange(spell, unit)
        if r ~= false and (not best or c.at > casts[best].at) then best = unit end
    end
    return best
end

local shown, testUntil
function Refresh(fresh)
    local now = GetTime()
    for unit, c in pairs(casts) do
        if now > c.stop or not plain(UnitExists(unit)) then casts[unit] = nil end
    end
    if testUntil and now < testUntil then return end
    testUntil = nil
    local unit = db and db.alert and Pick()
    if not unit then
        if shown then f:Hide(); shown = nil end
        return
    end
    local spell, left = NS.Pick(unit)
    local range = spell and InRange(spell, unit)
    local key = KeyText()
    f.icon:SetTexture((spell and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell))
        or (spell and GetSpellTexture and GetSpellTexture(spell)) or "Interface\\Icons\\Ability_Kick")
    local ready = spell and (not left or left == 0) and range ~= false
    if not spell then
        f.title:SetText("|cffff8080Enemy casting|r")
        f.how:SetText("no interrupt usable right now")
    elseif ready then
        f.title:SetText("|cffff4040INTERRUPT!|r")
        local where = unit == "target" and "" or ((key and key:find("attack key", 1, true)) and "target it, " or "hover it, ")
        f.how:SetText(key and (where .. "press " .. key .. " (" .. spell .. ")") or (spell .. " - bind a key: Keybindings > AddOns > TwizInterrupt"))
    elseif range == false then
        f.title:SetText("|cffffd040Enemy casting|r")
        f.how:SetText(spell .. ": out of range")
    else
        f.title:SetText("|cffffd040Enemy casting|r")
        f.how:SetText(("%s: ready in %.0fs"):format(spell, left))
    end
    SafeText(f.who, UnitName(unit), "Enemy")
    SafeText(f.what, casts[unit].name, "a spell")
    if not shown then f:Show() end
    if fresh and ready and db.sound and shown ~= unit and PlaySound then
        pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
    end
    shown = unit
end
NS.Refresh = Refresh

local acc = 0
f:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc < 0.1 then return end
    acc = 0
    if next(casts) or testUntil then Refresh() end
end)

function NS.Test()
    testUntil = GetTime() + 5
    local spell = NS.Pick("target") or (NS.List()[1] or {})[1]
    f.icon:SetTexture("Interface\\Icons\\Ability_Kick")
    f.title:SetText("|cffff4040INTERRUPT!|r")
    f.who:SetText("Defias Conjurer"); f.what:SetText("Fireball")
    local key = KeyText()
    f.how:SetText(spell and (key and ("press " .. key .. " (" .. spell .. ")") or (spell .. " - bind a key: Keybindings > AddOns > TwizInterrupt"))
        or "your class has no interrupt known yet")
    f:Show(); shown = "test"
    if db.sound and PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master") end
end

-- ---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "UNIT_PET",
    "UNIT_INVENTORY_CHANGED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "NAME_PLATE_UNIT_REMOVED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local queued
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "ADDON_LOADED" then
        if unit ~= ADDON then return end
        TwizInterruptDB = TwizInterruptDB or {}
        db = TwizInterruptDB
        for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
        NS.db = db
        Place()
        return
    end
    if not db then return end
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        Start(unit)
    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" or event == "NAME_PLATE_UNIT_REMOVED" then
        Stop(unit)
    elseif event:match("^UNIT_SPELLCAST_") then
        -- a channel's own "succeeded" fires at its start; only a real stop ends a channel
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            local c = UnitChannelInfo(unit)
            if secret(c) or c then return end
        end
        Stop(unit)
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
        local u = event == "PLAYER_TARGET_CHANGED" and "target" or "focus"
        casts[u] = nil
        Start(u)
        Refresh()
    else
        if event == "PLAYER_ENTERING_WORLD" and not db.told then
            db.told = true
            Print("bind your Interrupt key in Options > Keybindings > AddOns > TwizInterrupt. /interrupt test shows the alert.")
        end
        if (event == "UNIT_PET" or event == "UNIT_INVENTORY_CHANGED") and unit ~= "player" then return end
        if queued then return end
        queued = true
        C_Timer.After(0.1, function() queued = false; NS.Update() end)
    end
end)

_G["BINDING_HEADER_TWIZINTERRUPT"] = "TwizInterrupt"
_G["BINDING_NAME_CLICK TwizInterruptButton:LeftButton"] = "Interrupt (enemy under the mouse, else your target)"

local function onoff(v) return v and "on" or "off" end
SLASH_TWIZINTERRUPT1 = "/interrupt"
SLASH_TWIZINTERRUPT2 = "/tint"
SlashCmdList["TWIZINTERRUPT"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    local function flip(k, label) db[k] = not db[k]; Print(label .. " " .. onoff(db[k])); NS.Update(); Refresh() end
    local usage = "/interrupt alert | sound | nearby | hover | attack | unlock | lock | test | status"
    if cmd == "alert" then flip("alert", "cast alert")
    elseif cmd == "sound" then flip("sound", "alert sound")
    elseif cmd == "nearby" then flip("nearby", "alerts for nearby enemies in a fight (not just your target)")
    elseif cmd == "hover" then flip("hover", "interrupt the enemy under the mouse first")
    elseif cmd == "attack" then
        flip("attackKeys", "interrupt on the attack keys in a fight (fires whenever it's ready)")
        UpdateClassKeys()
    elseif cmd == "unlock" then db.locked = false; Place(); NS.Test(); Print("drag the alert where you want it, then /interrupt lock")
    elseif cmd == "lock" then db.locked = true; Place(); Print("alert locked")
    elseif cmd == "test" then NS.Test()
    elseif cmd == "status" or cmd == "" then
        local names = {}
        for _, e in ipairs(NS.List()) do names[#names + 1] = e[1] end
        Print(("interrupts known: %s. Key: %s. Alert %s, sound %s, nearby enemies %s, mouse-over first %s, on the attack keys %s.")
            :format(#names > 0 and table.concat(names, ", ") or "none yet", KeyText() or "not bound",
            onoff(db.alert), onoff(db.sound), onoff(db.nearby), onoff(db.hover), onoff(db.attackKeys)))
        if cmd == "" then Print(usage) end
    else
        Print(usage)
    end
end
TwizInterrupt = NS
