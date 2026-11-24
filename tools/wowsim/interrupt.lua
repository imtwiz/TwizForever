-- TwizInterrupt: the key per class and the cast alert
local L = function(s) SIM.log[#SIM.log + 1] = s end
local known = {}
C_Spell = C_Spell or {}
C_Spell.GetSpellInfo = function(n) local id = known[n]; return id and { spellID = id, name = n } end
IsPlayerSpell = function(id) for _, v in pairs(known) do if v == id then return true end end return false end
local cds = {}
C_Spell.GetSpellCooldown = function(n) local left = cds[n]; return left and { startTime = GetTime(), duration = left } or { startTime = 0, duration = 0 } end
local range = {}
C_Spell.IsSpellInRange = function(n, u) if range[u] == nil then return true end return range[u] end
local stance, shield = 1, false
SecureCmdOptionParse = function(s)
  local cond, rest = s:match("^%[(.-)%]%s*(.*)$")
  for c in cond:gmatch("[^,]+") do
    local st = c:match("^stance:(%d)$"); if st and tonumber(st) ~= stance then return nil end
    local nst = c:match("^nostance:(%d)$"); if nst and tonumber(nst) == stance then return nil end
    if c == "equipped:Shields" and not shield then return nil end
    local fm = c:match("^form:(.*)$")
    if fm then local ok = false; for x in fm:gmatch("%d") do if tonumber(x) == stance then ok = true end end; if not ok then return nil end end
  end
  return rest
end
local units = {}      -- token -> { name=, hostile=, cast=, noKick=, channel= }
UnitExists = function(u) return units[u] ~= nil end
UnitCanAttack = function(_, u) return units[u] and units[u].hostile or false end
UnitName = function(u) if u == "player" then return "Twiz" end return units[u] and units[u].name end
UnitIsUnit = function(a, b) return units[a] ~= nil and units[a] == units[b] end
UnitCastingInfo = function(u) local x = units[u]; if x and x.cast then return x.cast, "", 1, GetTime() * 1000, GetTime() * 1000 + 2000, false, 1, x.noKick, 123 end end
UnitChannelInfo = function() return nil end
local combat = false
UnitAffectingCombat = function(u) return u == "player" and combat end
local binds = {}
GetBindingKey = function(b) return binds[b] end
GetBindingText = function(k) return k end
local sounds = 0
PlaySound = function() sounds = sounds + 1 end
UnitCreatureFamily = function() return nil end

local cls = "WARRIOR"
UnitClass = function() return cls:lower(), cls end
known = { ["Pummel"] = 6552, ["Shield Bash"] = 72 }
SIM.LoadAddon(REPO .. "/TwizInterrupt", "TwizInterrupt")
SIM.Fire("ADDON_LOADED", "TwizInterrupt"); SIM.Fire("PLAYER_ENTERING_WORLD"); SIM.Advance(0.5)
local NS = TwizInterrupt
local function key() return tostring(TwizInterruptButton:GetAttribute("macrotext1")):gsub("\n", " || ") end
L("warrior key: " .. key())
assert(key():find("/cast %[@mouseover,harm,nodead,stance:3%]%[@target,harm,nodead,stance:3%] Pummel"))
assert(key():find("%[@mouseover,harm,nodead,equipped:Shields,nostance:3%]%[@target,harm,nodead,equipped:Shields,nostance:3%] Shield Bash"))

-- every class builds a key from what it knows
for c, spells in pairs({ ROGUE = { Kick = 1766, Gouge = 1776 }, MAGE = { Counterspell = 2139 }, SHAMAN = { ["Earth Shock"] = 8042 },
  PRIEST = { Silence = 15487 }, PALADIN = { ["Hammer of Justice"] = 853 }, HUNTER = { ["Scatter Shot"] = 19503 },
  DRUID = { Bash = 5211, ["Feral Charge"] = 16979 } }) do
  cls = c; known = spells
  SIM.Fire("SPELLS_CHANGED"); SIM.Advance(0.5)
  L(c .. ": " .. key())
  for s in pairs(spells) do assert(key():find(s, 1, true), c .. " missing " .. s) end
  if c == "DRUID" then assert(key():find("form:1%] Bash")) end
end
-- warlock with a felhunter out, pet spell not in the spellbook API
cls = "WARLOCK"; known = {}; UnitCreatureFamily = function() return "Felhunter" end
SIM.Fire("UNIT_PET", "player"); SIM.Advance(0.5)
L("warlock + felhunter: " .. key()); assert(key():find("Spell Lock"))

-- the alert: rogue, target starts a Fireball
cls = "ROGUE"; known = { Kick = 1766, Gouge = 1776 }; UnitCreatureFamily = function() return nil end
SIM.Fire("SPELLS_CHANGED"); SIM.Advance(0.5)
binds["CLICK TwizInterruptButton:LeftButton"] = "F"
units.target = { name = "Defias Conjurer", hostile = true, cast = "Fireball" }
SIM.Fire("UNIT_SPELLCAST_START", "target"); SIM.Advance(0.2)
local f = TwizInterruptAlert
L(("alert: %s | %s - %s | %s"):format(f.title:GetText(), f.who:GetText(), f.what:GetText(), f.how:GetText()))
assert(f:IsShown() and f.title:GetText():find("INTERRUPT") and f.how:GetText():find("press F %(Kick%)"))
assert(sounds == 1, "sound " .. sounds)
-- Kick on cooldown -> Gouge
cds.Kick = 8; SIM.Advance(0.2)
L("kick on cd: " .. f.how:GetText()); assert(f.how:GetText():find("Gouge"))
cds.Gouge = 8; SIM.Advance(0.2)
L("both on cd: " .. f.how:GetText()); assert(f.how:GetText():find("ready in"))
cds = {}
-- cast stops -> alert gone
SIM.Fire("UNIT_SPELLCAST_INTERRUPTED", "target"); SIM.Advance(0.2)
assert(not f:IsShown()); L("interrupted: alert hidden")
-- uninterruptible casts are ignored
units.target.noKick = true
SIM.Fire("UNIT_SPELLCAST_START", "target"); SIM.Advance(0.2)
assert(not f:IsShown()); L("can't be interrupted: no alert")
units.target.noKick = nil
-- friendly casters ignored
units.target = { name = "Priest friend", hostile = false, cast = "Heal" }
SIM.Fire("UNIT_SPELLCAST_START", "target"); SIM.Advance(0.2)
assert(not f:IsShown()); L("friendly cast: no alert")
-- nearby nameplate: only in a fight
units.target = nil
units.nameplate3 = { name = "Murloc Oracle", hostile = true, cast = "Healing Wave" }
SIM.Fire("UNIT_SPELLCAST_START", "nameplate3"); SIM.Advance(0.2)
assert(not f:IsShown()); L("nameplate out of combat: no alert")
combat = true
SIM.Fire("UNIT_SPELLCAST_START", "nameplate3"); SIM.Advance(0.2)
L("nameplate in combat: " .. f.who:GetText() .. " | " .. f.how:GetText())
assert(f:IsShown() and f.how:GetText():find("hover it, press F"))
-- out of range nearby enemy -> not shown
SIM.Fire("UNIT_SPELLCAST_STOP", "nameplate3"); SIM.Advance(0.2)
range.nameplate3 = false
SIM.Fire("UNIT_SPELLCAST_START", "nameplate3"); SIM.Advance(0.2)
assert(not f:IsShown()); L("nameplate out of range: no alert")
-- cast ends by its own time without a stop event
range.nameplate3 = nil
SIM.Fire("UNIT_SPELLCAST_START", "nameplate3"); SIM.Advance(0.2); assert(f:IsShown())
SIM.Advance(3); assert(not f:IsShown()); L("cast time over: alert hidden")
-- warrior in Berserker Stance picks Pummel, in Battle Stance with a shield Shield Bash
cls = "WARRIOR"; known = { ["Pummel"] = 6552, ["Shield Bash"] = 72 }
stance = 3; L("berserker: " .. tostring(NS.Pick("target"))); assert(NS.Pick("target") == "Pummel")
stance = 1; shield = true; L("battle + shield: " .. tostring(NS.Pick("target"))); assert(NS.Pick("target") == "Shield Bash")
shield = false; assert(NS.Pick("target") == nil); L("battle, no shield: nothing usable")
-- slash + test
SlashCmdList.TWIZINTERRUPT("hover"); assert(not key():find("mouseover")); L("hover off: " .. key())
SlashCmdList.TWIZINTERRUPT("test"); assert(f:IsShown())
SlashCmdList.TWIZINTERRUPT("")
