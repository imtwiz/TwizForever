-- TwizWarrior: one-key warrior.
--   Attack key (Options > Keybindings > AddOns > TwizWarrior):
--     auto attack; per target: Battle Shout (only when it was missing as the fight started), then
--     Rend once; then Heroic Strike on every press (it waits for your next swing, so it doesn't
--     block the rest), Execute when the target is low enough to allow it, Overpower right after the
--     target dodges (Battle Stance), Revenge after you block, dodge or parry (Defensive Stance), and
--     Victory Rush when it's up after a kill.
--     /warrior hs turns the Heroic Strike dump off if you're short on rage (Forever's rage is
--     tighter than Classic's).
--   Charge key: Charge out of combat, Intercept in combat (once you know it).
--   Interrupt key: Pummel, or Shield Bash with a shield on.
-- The game locks keys in combat and hides health and buffs from addons, so the order is fixed;
-- spells that aren't usable right now (Execute, Victory Rush) are simply skipped by the game.
local ADDON, NS = ...
local db
local DEFAULTS = { shout = true, rend = true, hs = true, overpower = true, revenge = true }

local function Print(m) DEFAULT_CHAT_FRAME:AddMessage("|cffc79c6eTwizWarrior|r: " .. tostring(m)) end
local function plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end

local function Known(name)
    if not name then return false end
    local id
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        id = ok and info and info.spellID
    elseif GetSpellInfo then
        id = select(7, GetSpellInfo(name))
    end
    if not id then return false end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return false
end
NS.Known = Known

local function HasBuff(unit, name)
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, "HELPFUL")
        if ok then return a ~= nil end
    end
    return false
end

local btn = CreateFrame("Button", "TwizWarriorButton", UIParent, "SecureActionButtonTemplate")
btn:RegisterForClicks("AnyUp", "AnyDown")
btn:SetAttribute("type", "macro")
btn:Hide()

local T = "@target,harm,nodead"

local function AttackMacro()
    local lines = { ("/startattack [%s]"):format(T) }
    local seq = {}
    -- Battle Shout only when it's missing now (out of combat is when this is decided)
    if db.shout and Known("Battle Shout") and not HasBuff("player", "Battle Shout") then seq[#seq + 1] = "Battle Shout" end
    if db.rend and Known("Rend") then seq[#seq + 1] = "Rend" end
    if #seq > 0 then
        lines[#lines + 1] = ("/castsequence [%s] reset=target %s, null"):format(T, table.concat(seq, ", "))
    end
    if db.hs and Known("Heroic Strike") then lines[#lines + 1] = ("/cast [%s] Heroic Strike"):format(T) end
    if Known("Execute") then lines[#lines + 1] = ("/cast [%s] Execute"):format(T) end
    -- 1.1.0: Overpower whenever the target has just dodged (Battle Stance only; the game only
    -- allows it for a few seconds after a dodge, so most presses it's just skipped)
    if db.overpower and Known("Overpower") then lines[#lines + 1] = ("/cast [stance:1,%s] Overpower"):format(T) end
    -- 1.2.0: Revenge whenever the game allows it (after you block, dodge or parry; Defensive Stance)
    if db.revenge and Known("Revenge") then lines[#lines + 1] = ("/cast [stance:2,%s] Revenge"):format(T) end
    if Known("Victory Rush") then lines[#lines + 1] = ("/cast [%s] Victory Rush"):format(T) end
    return table.concat(lines, "\n")
end

local function ChargeMacro()
    if Known("Charge") and Known("Intercept") then return ("/cast [nocombat,%s] Charge; [%s] Intercept"):format(T, T) end
    if Known("Charge") then return ("/cast [%s] Charge"):format(T) end
    return ""
end

local function InterruptMacro()
    local shield = GetInventoryItemLink and GetInventoryItemLink("player", 17)
    local isShield = shield and select(7, GetItemInfo(shield)) == "Shields"
    if isShield and Known("Shield Bash") then return ("/cast [%s] Shield Bash"):format(T) end
    if Known("Pummel") then return ("/cast [%s] Pummel"):format(T) end
    if Known("Shield Bash") then return ("/cast [%s] Shield Bash"):format(T) end
    return ""
end

function NS.Update()
    if not db or InCombatLockdown() then return end
    local m1 = AttackMacro()
    if btn:GetAttribute("macrotext1") ~= m1 then btn:SetAttribute("macrotext1", m1) end
    local m2 = ChargeMacro()
    if btn:GetAttribute("macrotext2") ~= m2 then btn:SetAttribute("macrotext2", m2) end
    local m3 = InterruptMacro()
    if btn:GetAttribute("macrotext3") ~= m3 then btn:SetAttribute("macrotext3", m3) end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "UNIT_AURA",
    "UNIT_INVENTORY_CHANGED", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local queued
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        TwizWarriorDB = TwizWarriorDB or {}
        db = TwizWarriorDB
        for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
        NS.db = db
        return
    end
    if not db or select(2, UnitClass("player")) ~= "WARRIOR" then return end
    if (event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED") and a1 ~= "player" then return end
    if event == "PLAYER_ENTERING_WORLD" and not db.told then
        db.told = true
        Print("bind your keys in Options > Keybindings > AddOns > TwizWarrior: Attack (one key does it all), Charge, Interrupt. /warrior for settings.")
    end
    if queued then return end
    queued = true
    C_Timer.After(0.1, function() queued = false; NS.Update() end)
end)

_G["BINDING_HEADER_TWIZWARRIOR"] = "TwizWarrior"
_G["BINDING_NAME_CLICK TwizWarriorButton:LeftButton"] = "Attack (shout, Rend, Heroic Strike, Execute, Overpower, Revenge, Victory Rush)"
_G["BINDING_NAME_CLICK TwizWarriorButton:RightButton"] = "Charge (Intercept in combat)"
_G["BINDING_NAME_CLICK TwizWarriorButton:MiddleButton"] = "Interrupt (Pummel / Shield Bash)"

local function onoff(v) return v and "on" or "off" end
SLASH_TWIZWARRIOR1 = "/warrior"
SLASH_TWIZWARRIOR2 = "/twizwarrior"
SlashCmdList["TWIZWARRIOR"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    local function flip(k, label) db[k] = not db[k]; Print(label .. " " .. onoff(db[k])); NS.Update() end
    if cmd == "shout" then flip("shout", "Battle Shout when missing")
    elseif cmd == "rend" then flip("rend", "Rend once per target")
    elseif cmd == "hs" then flip("hs", "Heroic Strike on every press")
    elseif cmd == "overpower" or cmd == "op" then flip("overpower", "Overpower after a dodge")
    elseif cmd == "revenge" then flip("revenge", "Revenge after a block, dodge or parry")
    elseif cmd == "status" or cmd == "" then
        Print(("Battle Shout %s, Rend %s, Heroic Strike %s, Overpower %s, Revenge %s."):format(onoff(db.shout), onoff(db.rend), onoff(db.hs), onoff(db.overpower), onoff(db.revenge)))
        if cmd == "" then Print("/warrior shout | rend | hs | overpower | revenge | status") end
    else
        Print("/warrior shout | rend | hs | overpower | revenge | status")
    end
end
TwizWarrior = NS
