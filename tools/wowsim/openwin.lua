-- Craft All opens (or switches to) the profession window, then crafts
local f = io.open(REPO .. "/tools/wowsim/planmake.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("local plan, why") - 1)
assert(loadstring(src))()
local NS = TwizCraft
local profs = NS.Char().profs
for _, r in pairs(profs[202].recipes) do r.learned = true end
profs[185] = { name = "Cooking", line = 185, recipes = { [2538] = { name = "Charred Wolf Meat", out = 2679, made = 1, orange = 1, yellow = 45, green = 65, gray = 85, learned = true, reagents = { { id = 2672, qty = 1 } } } } }
SIM.open = nil
ProfessionsFrame = CreateFrame("Frame", "ProfessionsFrame", UIParent); ProfessionsFrame:Hide()
C_TradeSkillUI.GetBaseProfessionInfo = function() return SIM.open and { professionID = SIM.open } or {} end
C_TradeSkillUI.OpenTradeSkill = function(line)
  SIM.calls[#SIM.calls + 1] = { "OpenTradeSkill", line }
  C_Timer.After(0.3, function() SIM.open = line; ProfessionsFrame:Show(); SIM.Fire("TRADE_SKILL_SHOW") end)
  C_Timer.After(0.6, function() SIM.Fire("TRADE_SKILL_LIST_UPDATE") end)
  return true
end
SIM.casting = nil
UnitCastingInfo = function() return SIM.casting end
C_TradeSkillUI.CraftRecipe = function(id, count)
  SIM.calls[#SIM.calls + 1] = { "CraftRecipe", id, count }
  SIM.casting = "craft"; SIM.Fire("UNIT_SPELLCAST_START", "player"); C_Timer.After(1, function() SIM.casting = nil; SIM.Fire("UNIT_SPELLCAST_STOP", "player") end)
end
NS.SkillFor = function() return 80, 150 end
SIM.PutInBags(2836, 6)
local L = function(s) SIM.log[#SIM.log + 1] = s end
local function calls() local o = {} for _, c in ipairs(SIM.calls) do o[#o + 1] = c[1] .. " " .. tostring(c[2]) .. (c[3] and (" x" .. c[3]) or "") end return table.concat(o, ", ") end
L("=== window closed")
SIM.calls = {}; NS.CraftAll(); SIM.Advance(3)
L("calls: " .. calls())
L("=== Cooking window open, nothing to cook")
SIM.PutInBags(2836, 4); SIM.open = 185; NS.currentPlan = nil
SIM.calls = {}; NS.CraftAll(); SIM.Advance(3)
L("calls: " .. calls())
-- the game refuses to start a craft right after opening: say so, next press works
L("=== game won't craft right after opening")
SIM.PutInBags(2836, 3); SIM.open = nil; ProfessionsFrame:Hide()
local realCraft = C_TradeSkillUI.CraftRecipe
C_TradeSkillUI.CraftRecipe = function(id, n) SIM.calls[#SIM.calls + 1] = { "CraftRecipe(refused)", id, n } end
SIM.calls = {}; NS.CraftAll(); SIM.Advance(3)
C_TradeSkillUI.CraftRecipe = realCraft
NS.CraftAll(); SIM.Advance(3)
L("calls: " .. calls())
