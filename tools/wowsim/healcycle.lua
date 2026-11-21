-- TwizHeal 1.15: combat cycle by spell ID (sized Healing Touch rank), run as restricted code
SecureHandlerWrapScript = function(frame, script, header, pre) frame.__pre = pre end
local f = io.open(REPO .. "/tools/wowsim/healrules.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("SIM.Advance%(0.3%); L%(\"1 tank 90%%") - 1)
local rest = [==[
local NS = TwizHeal
local L = function(s) SIM.log[#SIM.log + 1] = s end
SIM.Advance(0.3)
local key = tostring(TwizHealButton:GetAttribute("macrotext1"))
L("combat line: " .. (key:match("/click %[combat%][^\n]+") or key))
local cyc = TwizHealCycleKey
L("cycle ids: " .. tostring(cyc and cyc:GetAttribute("cycleids")) .. " | combat Healing Touch: rank " .. tostring(NS.CombatDirect() and NS.CombatDirect().rank))
-- run the restricted snippet like the game would: only secure functions exist (no GetTime, no strsplit)
local target = "party1"
local env = setmetatable({ self = cyc, SecureCmdOptionParse = function(o) return target end }, { __index = function(_, k) error("restricted code has no " .. tostring(k)) end })
local fn = assert(loadstring(cyc.__pre)); setfenv(fn, env)
local casts = {}
for i = 1, 5 do fn(); casts[#casts + 1] = tostring(cyc:GetAttribute("spell")) .. "@" .. tostring(cyc:GetAttribute("unit")) end
L("5 presses on the tank: " .. table.concat(casts, ", "))
target = "party2"; fn()
L("new target -> starts over: " .. tostring(cyc:GetAttribute("spell")) .. "@" .. tostring(cyc:GetAttribute("unit")))
SlashCmdList.TWIZHEAL("combatrank 1"); SIM.Advance(0.3)
L("/th combatrank 1 -> ids " .. tostring(cyc:GetAttribute("cycleids")))
local gsi = C_Spell.GetSpellInfo
C_Spell.GetSpellInfo = function(n) if n == "Swiftmend" then return { name = n, spellID = 18562 } end return gsi and gsi(n) end
SlashCmdList.TWIZHEAL("combatrank"); SIM.Advance(0.3)
L("with Swiftmend learned -> ids " .. tostring(cyc:GetAttribute("cycleids")))
]==]
assert(loadstring(src .. "\n" .. rest))()
