-- Craft All against Alan's real TwizCraft saved data
dofile("/tmp/realsv/TwizCraft.lua")
local realUN = UnitName
UnitName = function(u) if u == "player" then return "Kitty" end return realUN(u) end
GetRealmName = function() return "CAMWOW US2 Realm 6 PvP" end
GetNormalizedRealmName = function() return "CAMWOWUS2Realm6PvP" end
SIM.items[2836] = { name = "Coarse Stone", vendor = 15, classID = 7 }
SIM.items[4364] = { name = "Coarse Blasting Powder", vendor = 12, classID = 7 }
local NS = SIM.LoadAddon(REPO .. "/TwizCraft", "TwizCraft")
SIM.Fire("ADDON_LOADED", "TwizCraft"); SIM.Fire("PLAYER_LOGIN"); SIM.Advance(3)
local L = function(s) SIM.log[#SIM.log + 1] = s end
-- which character key is used?
local chars = {}
for k in pairs(CraftRouteDB.chars or {}) do chars[#chars + 1] = k end
L("chars in SV: " .. table.concat(chars, ", "))
local prof = NS.Char().profs and NS.Char().profs[202]
L("NS.Char() has engineering: " .. tostring(prof ~= nil))
C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionID = 202, professionName = "Engineering" } end
C_TradeSkillUI.GetRecipeRepeatCount = function() return 0 end
C_TradeSkillUI.CraftRecipe = function(id, n) SIM.calls[#SIM.calls + 1] = { "CraftRecipe", id, n } end
SIM.PutInBags(2836, 20)
for _, skill in ipairs({ 80, 92, 100 }) do
  NS.SkillFor = function() return skill, 150 end
  local ok, q, grays = pcall(NS.CraftAllQueue)
  if not ok then L(("skill %d: CraftAllQueue ERROR %s"):format(skill, tostring(q)))
  else
    local names = {}
    for _, e in ipairs(q) do names[#names + 1] = e.r.name .. " x" .. tostring(e.want) end
    L(("skill %d: queue [%s] grays [%s]"):format(skill, table.concat(names, ", "), table.concat(grays or {}, ", ")))
  end
  local ok2, err = pcall(NS.CraftAll)
  if not ok2 then L("CraftAll ERROR: " .. tostring(err)) end
end
