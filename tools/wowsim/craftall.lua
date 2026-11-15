-- TwizCraft Craft All: make-first batch, then each step, one batch per press
local f = io.open(REPO .. "/tools/wowsim/planmake.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("local plan, why") - 1)
assert(loadstring(src))()
local NS = TwizCraft
for _, r in pairs(NS.Char().profs[202].recipes) do r.learned = true end
SIM.casting = nil
UnitCastingInfo = function(u) return SIM.casting end
C_TradeSkillUI = C_TradeSkillUI or {}
C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionID = 202 } end
C_TradeSkillUI.GetRecipeRepeatCount = function() return 0 end
-- crafting turns reagents into the product instantly, then the cast "stops"
C_TradeSkillUI.CraftRecipe = function(id, count)
  SIM.calls[#SIM.calls + 1] = { "CraftRecipe", id, count }
  local r = NS.Char().profs[202].recipes[id]
  for _, g in ipairs(r.reagents) do SIM.TakeFromBags(g.id, g.qty * count) end
  SIM.PutInBags(r.out, (r.made or 1) * count)
  SIM.casting = r.name
  C_Timer.After(1, function() SIM.casting = nil; SIM.Fire("UNIT_SPELLCAST_STOP", "player") end)
end
SIM.PutInBags(2836, 30)   -- Coarse Stone
SIM.PutInBags(2589, 10)   -- Linen Cloth
local plan = NS.PlanFor(202)
NS.currentPlan = plan; NS.current = 202
local L = function(s) SIM.log[#SIM.log + 1] = s end
local q = NS.CraftAllQueue()
local names = {}
for _, e in ipairs(q) do names[#names + 1] = e.r.name .. " x" .. tostring(e.want) end
L("queue: " .. table.concat(names, ", "))
SIM.Fire("TRADE_SKILL_SHOW"); SIM.Advance(0.5)
L("wheel bound: " .. tostring(SIM.overrides["MOUSEWHEELDOWN"]))
for press = 1, 4 do
  NS.CraftAll(); SIM.Advance(0.2)
  NS.CraftAll()              -- impatient second press while the batch runs: ignored
  SIM.Advance(2)
end
local crafts = {}
for _, c in ipairs(SIM.calls) do if c[1] == "CraftRecipe" then crafts[#crafts + 1] = NS.Char().profs[202].recipes[c[2]].name .. " x" .. c[3] end end
L("crafted: " .. table.concat(crafts, ", "))
L(("bags: stone %d, powder %d, dynamite %d, linen %d"):format(NS.BagCount(2836), NS.BagCount(4364), NS.BagCount(4365), NS.BagCount(2589)))
L("wheel after: " .. tostring(SIM.overrides["MOUSEWHEELDOWN"]))

-- case 2: TwizCraft window set to another profession (no engineering plan), skill 80
L("=== plan for another profession, engineering window open")
SIM.PutInBags(2836, 5)
NS.currentPlan = nil; NS.current = 185
NS.SkillFor = function() return 80, 150 end
SIM.calls = {}
NS.CraftAll(); SIM.Advance(2)
for _, c in ipairs(SIM.calls) do if c[1] == "CraftRecipe" then L("crafted: " .. NS.Char().profs[202].recipes[c[2]].name .. " x" .. c[3]) end end
-- case 3: skill 96 -> powder is gray
L("=== skill 96, powder gray")
SIM.PutInBags(2836, 4)
NS.SkillFor = function() return 96, 150 end
SIM.calls = {}
NS.CraftAll(); SIM.Advance(2)
local n = 0 for _, c in ipairs(SIM.calls) do if c[1] == "CraftRecipe" then n = n + 1 end end
L("crafts without shift: " .. n)
IsShiftKeyDown = function() return true end
NS.CraftAll(); SIM.Advance(2)
IsShiftKeyDown = function() return false end
for _, c in ipairs(SIM.calls) do if c[1] == "CraftRecipe" then L("shift-click crafted: " .. NS.Char().profs[202].recipes[c[2]].name .. " x" .. c[3]) end end
