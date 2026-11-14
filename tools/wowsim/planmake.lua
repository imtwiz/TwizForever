-- TwizCraft planner: making Coarse Blasting Powder (gives skill-ups) instead of buying it
local REPO = REPO
SIM.items[2836] = { name = "Coarse Stone", vendor = 15, classID = 7 }
SIM.items[4364] = { name = "Coarse Blasting Powder", vendor = 12, classID = 7 }
SIM.items[4365] = { name = "Coarse Dynamite", vendor = 30, classID = 0 }
SIM.items[2589] = { name = "Linen Cloth", vendor = 13, classID = 7 }
local NS = SIM.LoadAddon(REPO .. "/TwizCraft", "TwizCraft")
SIM.Fire("ADDON_LOADED", "TwizCraft"); SIM.Fire("PLAYER_LOGIN"); SIM.Advance(2)
local prices = { [2836] = 60, [4364] = 40, [2589] = 25, [4365] = 79 }
NS.AHPrice = function(id) return prices[id] end
NS.VendorBuy = function() return nil end
NS.SkillFor = function() return 75, 150 end
local recipes = {
  [3929] = { name = "Coarse Blasting Powder", out = 4364, made = 1, orange = 75, yellow = 85, green = 90, gray = 95, cast = 5,
             learned = false, reagents = { { id = 2836, qty = 1 } } },
  [3931] = { name = "Coarse Dynamite", out = 4365, made = 2, orange = 75, yellow = 90, green = 97, gray = 105, cast = 5,
             learned = false, reagents = { { id = 4364, qty = 3 }, { id = 2589, qty = 1 } } },
}
NS.Char().profs = { [202] = { name = "Engineering", line = 202, recipes = recipes } }
NS.db.target = { [202] = 100 }
local plan, why = NS.PlanFor(202)
if not plan then SIM.log[#SIM.log + 1] = "no plan: " .. tostring(why) return end
for _, st in ipairs(plan.steps) do
  local mk = {}
  for id in pairs(st.make or {}) do mk[#mk + 1] = SIM.items[id].name end
  SIM.log[#SIM.log + 1] = ("step %d-%d %s%s x%d  cost %s%s"):format(st.from, st.to, st.learn and "[learn] " or "", st.r.name, st.n,
     NS.Money(st.cost), #mk > 0 and ("  (make: " .. table.concat(mk, ", ") .. ")") or "")
end
for _, sc in ipairs(plan.subcrafts or {}) do SIM.log[#SIM.log + 1] = ("make first: %s%d %s"):format(sc.learn and "[learn] " or "", sc.n, sc.name) end
for _, e in ipairs(plan.shop) do SIM.log[#SIM.log + 1] = ("buy %d %s (%s)"):format(e.buy, SIM.items[e.id].name, e.src) end
SIM.log[#SIM.log + 1] = ("total %s for 75->100, %d crafts"):format(NS.Money(plan.cost), plan.crafts)
