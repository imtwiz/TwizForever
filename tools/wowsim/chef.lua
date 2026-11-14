-- TwizChef scenario: learn recipes, plan at a vendor (ingredients + water restock),
-- quest protection, cook key, eat key, Well Fed reminder.
local REPO = REPO
local function item(id, name, vendor, use, req)
    SIM.items[id] = { name = name, vendor = vendor or 1, classID = 0, subID = 5, quality = 1 }
    if use then SIM.tooltips[id] = use end
end
-- ingredients
item(2672, "Stringy Wolf Meat", 1); SIM.items[2672].classID = 7
item(769,  "Chunk of Boar Meat", 1); SIM.items[769].classID = 7
item(2678, "Mild Spices", 1); SIM.items[2678].classID = 7
-- foods
item(2680, "Spiced Wolf Meat", 6, "Restores 61 health over 18 sec. If you spend at least 10 seconds eating you will become well fed and gain 2 Stamina and Spirit for 15 min.")
item(2681, "Roasted Boar Meat", 6, "Restores 61 health over 18 sec.")
item(117,  "Tough Jerky", 1, "Restores 61 health over 18 sec.")
item(1179, "Ice Cold Milk", 1, "Restores 437 mana over 18 sec.")
item(159,  "Refreshing Spring Water", 1, "Restores 151 mana over 18 sec.")
-- recipes the cooking window would show
local recipes = {
    [2539] = { name = "Spiced Wolf Meat", out = 2680, reagents = { { 2672, 1 }, { 2678, 1 } } },
    [2540] = { name = "Roasted Boar Meat", out = 2681, reagents = { { 769, 1 } } },
}
C_TradeSkillUI.GetBaseProfessionInfo = function() return SIM.cookingOpen and { professionID = 185, professionName = "Cooking" } or nil end
C_TradeSkillUI.GetAllRecipeIDs = function() local t = {} for id in pairs(recipes) do t[#t + 1] = id end return t end
C_TradeSkillUI.GetRecipeInfo = function(id) return recipes[id] and { name = recipes[id].name, learned = true, relativeDifficulty = 1 } end
C_TradeSkillUI.GetRecipeSchematic = function(id) local r = recipes[id] if not r then return nil end
    local slots = {} for _, g in ipairs(r.reagents) do slots[#slots + 1] = { required = true, quantityRequired = g[2], reagents = { { itemID = g[1] } } } end
    return { name = r.name, outputItemID = r.out, reagentSlotSchematics = slots } end
C_TradeSkillUI.OpenTradeSkill = function(line) SIM.calls[#SIM.calls + 1] = { "OpenTradeSkill", line } SIM.cookingOpen = true return true end
C_TradeSkillUI.CraftRecipe = function(id, n) SIM.calls[#SIM.calls + 1] = { "CraftRecipe", id, n } end
GetProfessions = function() return nil, nil, nil, nil, 5 end
GetProfessionInfo = function() return "Cooking", 0, 50, 75, 0, 0, 185 end

local ns = SIM.LoadAddon(REPO .. "/TwizChef", "TwizChef")
SIM.Fire("ADDON_LOADED", "TwizChef"); SIM.Fire("PLAYER_LOGIN"); SIM.Advance(6)

-- learn recipes
SIM.cookingOpen = true; SIM.Fire("TRADE_SKILL_SHOW"); SIM.Advance(1); SIM.cookingOpen = false

-- bags: 10 wolf meat (a quest wants boar meat), 3 boar meat, 2 spring water
SIM.PutInBags(2672, 10); SIM.PutInBags(769, 3); SIM.PutInBags(159, 2); SIM.PutInBags(2680, 4); SIM.PutInBags(117, 5)
SIM.quests = { { title = "Boar Meat for Mrs. Dobbins", questID = 1, isHeader = false, objectives = { { type = "item", text = "Chunk of Boar Meat: 0/4" } } } }

-- vendor sells spices, water and milk
SIM.merchant = { { id = 2678, price = 10, stack = 1 }, { id = 159, price = 25, stack = 1 }, { id = 1179, price = 100, stack = 1 }, { id = 117, price = 25, stack = 1 } }
SIM.OpenMerchant(); SIM.Advance(6); SIM.CloseMerchant()

-- eat key
SIM.Fire("BAG_UPDATE_DELAYED"); SIM.Advance(1)
local b = TwizChefEatButton
SIM.log[#SIM.log + 1] = "eat macro (not well fed): " .. tostring(b and b:GetAttribute("macrotext"))
SIM.auras = { "Well Fed" }; SIM.Fire("UNIT_AURA", "player"); SIM.Advance(1)
SIM.log[#SIM.log + 1] = "eat macro (well fed): " .. tostring(b and b:GetAttribute("macrotext"))
SIM.auras = {}

-- cook key: first press opens Cooking, second cooks
TwizChef.CookNext(); SIM.Advance(0.5); TwizChef.CookNext()

-- leaving town without Well Fed
SIM.resting = false; SIM.Fire("PLAYER_UPDATE_RESTING"); SIM.Advance(2)
