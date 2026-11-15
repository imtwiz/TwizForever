-- TwizAH: recipes in the bank are remembered (never re-bought) and learnable ones are taken out
ADDON_DIR = REPO .. "/TwizAH"
dofile(REPO .. "/tools/wowsim/scenario.lua")
local ns = TwizAH
local L = function(s) SIM.log[#SIM.log + 1] = s end
GetProfessions = function() return 1 end
GetProfessionInfo = function() return "Tailoring", 0, 120 end
SIM.tooltipLines = SIM.tooltipLines or {}
local function recipe(id, name, price, level)
    SIM.items[id] = { name = name, vendor = 10, classID = 9, subID = 2, quality = 1 }
    SIM.tooltipLines[id] = { "Requires Tailoring (" .. level .. ")" }
    SIM.ah[id] = { commodity = false, listings = { { unit = price, qty = 1, auctionID = id * 10 } } }
    ns.db.market[id] = { min = price, med = price, n = 1, q = 1, t = time() }
end
recipe(9001, "Pattern: Banked Learnable", 1000, 50)
recipe(9002, "Pattern: Banked For Later", 1100, 150)
recipe(9003, "Pattern: Not Owned", 1200, 50)
SIM.bags["-1:1"] = { id = 9001, count = 1 }
SIM.bags["-1:2"] = { id = 9002, count = 1 }
local moved = {}
local realUse = C_Container.UseContainerItem
C_Container.UseContainerItem = function(bag, slot)
    if bag == -1 then
        local sl = SIM.bags[bag .. ":" .. slot]
        if sl then SIM.bags[bag .. ":" .. slot] = nil; SIM.PutInBags(sl.id, sl.count); moved[#moved + 1] = SIM.items[sl.id].name end
        return
    end
    return realUse(bag, slot)
end
SIM.Fire("BANKFRAME_OPENED"); SIM.Advance(2)
L("taken out of the bank: " .. table.concat(moved, ", "))
local store = ns.db.recipeBank[UnitName("player") .. "-" .. GetRealmName()] or {}
local t = {} for id in pairs(store) do t[#t + 1] = SIM.items[id].name end table.sort(t)
L("remembered in bank: " .. table.concat(t, ", "))
SIM.Fire("BANKFRAME_CLOSED"); SIM.Advance(1)
-- later, at the AH (bank closed, GetItemCount can't see the bank): the banked one must not be offered
local realCount = C_Item.GetItemCount
C_Item.GetItemCount = function(id, bank) if id == 9002 then return 0 end return realCount(id, bank) end
GetProfessionInfo = function() return "Tailoring", 0, 160 end -- skill went up: 9002 is learnable now
AuctionHouseFrame.__shown = true; SIM.Fire("AUCTION_HOUSE_SHOW"); SIM.Advance(1)
local names = {} for _, r in ipairs(ns.RecipeList()) do names[#names + 1] = SIM.items[r.itemID].name end
L("offered at the AH: " .. table.concat(names, ", "))
