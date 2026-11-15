-- TwizAH: recipe names show even before the item is cached (no "item 4410")
ADDON_DIR = REPO .. "/TwizAH"
dofile(REPO .. "/tools/wowsim/scenario.lua")
local ns = TwizAH
GetProfessions = function() return 1 end
GetProfessionInfo = function() return "Tailoring", 0, 120 end
SIM.tooltipLines = SIM.tooltipLines or {}
SIM.items[4410] = { name = "Schematic: Shadow Goggles", vendor = 10, classID = 9, subID = 3, quality = 1 }
SIM.tooltipLines[4410] = { "Requires Tailoring (50)" }
SIM.ah[4410] = { commodity = false, listings = { { unit = 900, qty = 1, auctionID = 44100 } } }
ns.db.market[4410] = { min = 900, med = 900, n = 1, q = 1, t = time() }
local realInfo = C_Item.GetItemInfo
C_Item.GetItemInfo = function(id) if id == 4410 then return nil end return realInfo(id) end -- not cached yet
SIM.onPlaceBid = function(auctionID, amount) C_Timer.After(0.3, function() SIM.money = SIM.money - amount; SIM.Fire("PLAYER_MONEY") end) end
AuctionHouseFrame.__shown = true; SIM.Fire("AUCTION_HOUSE_SHOW"); SIM.Advance(10)
ns.S.recipeBudget = 100000; ns.db.recipeSpent = 0
local f = ns.UI._frame(); f:Show(); ns.UI.SetTab("RECIPES"); SIM.Advance(1)
ns.extraTabs.RECIPES.__buttons[1]:Click(); SIM.Advance(3)
local found = {}
for _, m in ipairs(SIM.log) do if m:find("Bought") then found[#found + 1] = m end end
for _, m in ipairs(found) do SIM.log[#SIM.log + 1] = "MSG: " .. m end
