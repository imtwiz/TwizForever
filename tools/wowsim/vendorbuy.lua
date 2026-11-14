-- TwizCraft vendor buying: spam-clicking Buy and TwizChef buying first must not overbuy
local REPO = REPO
SIM.items[2678] = { name = "Mild Spices", vendor = 1, classID = 7 }
SIM.items[159]  = { name = "Refreshing Spring Water", vendor = 1, classID = 0 }
local NS = SIM.LoadAddon(REPO .. "/TwizCraft", "TwizCraft")
SIM.Fire("ADDON_LOADED", "TwizCraft"); SIM.Fire("PLAYER_LOGIN"); SIM.Advance(2)
SIM.money = 10000000
SIM.merchant = { { id = 2678, price = 10, stack = 1 }, { id = 159, price = 25, stack = 5 } }
NS.merchantOpen = true
local plan = { shop = { { id = 2678, need = 20, buy = 20, src = "vendor", unit = 10 },
                        { id = 159,  need = 12, buy = 12, src = "vendor", unit = 5 } } }
-- spam the button 5 times
for i = 1, 5 do NS.BuyFromVendor(plan) end
SIM.Advance(10)
SIM.log[#SIM.log + 1] = ("after 5 clicks: spices %d (want 20), water %d (want 12, sold in 5s -> 15)"):format(NS.BagCount(2678), NS.BagCount(159))
-- click again after it's done: nothing more should be bought (plan still stale: buy=20)
NS.BuyFromVendor(plan); SIM.Advance(5)
SIM.log[#SIM.log + 1] = ("click again with a stale plan: spices %d, water %d"):format(NS.BagCount(2678), NS.BagCount(159))
-- TwizChef-style outside purchase: someone else already bought 8 of a new 30-need
local plan2 = { shop = { { id = 2678, need = 50, buy = 30, src = "vendor", unit = 10 } } }
SIM.PutInBags(2678, 8)
NS.BuyFromVendor(plan2); SIM.Advance(10)
SIM.log[#SIM.log + 1] = ("need 50, had 28 then got: spices %d (want 50)"):format(NS.BagCount(2678))
