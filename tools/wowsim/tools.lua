-- TwizAH: keep one of each profession tool; spares can be sold
local REPO = REPO
SIM.items[6219] = { name = "Arclight Spanner", vendor = 25, classID = 7 }
SIM.items[4471] = { name = "Flint and Tinder", vendor = 1, classID = 15 }
SIM.items[2901] = { name = "Mining Pick", vendor = 20, classID = 2 }
SIM.items[5956] = { name = "Blacksmith Hammer", vendor = 4, classID = 7 }
SIM.items[40772] = { name = "Gnomish Army Knife", vendor = 1000, classID = 7 }
local ns = SIM.LoadAddon(REPO .. "/TwizAH", "TwizAH")
SIM.Fire("ADDON_LOADED", "TwizAH"); SIM.Fire("PLAYER_LOGIN"); SIM.Advance(2)
local function names(res)
  local out = {}
  for key in pairs(res) do
    local bag, slot = key:match("(%d+):(%d+)")
    local info = C_Container.GetContainerItemInfo(tonumber(bag), tonumber(slot))
    out[#out + 1] = info and SIM.items[info.itemID].name or key
  end
  table.sort(out); return table.concat(out, ", ")
end
SIM.PutInBags(6219, 1); SIM.PutInBags(6219, 1)        -- two spanners
SIM.PutInBags(4471, 1)                                -- flint and tinder
SIM.PutInBags(2901, 1, true); SIM.PutInBags(2901, 1)  -- a soulbound pick + a spare
SIM.log[#SIM.log + 1] = "kept: " .. names(ns.ToolReserve())
SIM.log[#SIM.log + 1] = ("tools never bought on AH: spanner %s, flint %s"):format(tostring(ns.IsExcluded(6219)), tostring(ns.IsExcluded(4471)))
-- add a Gnomish Army Knife: it covers spanner, pick, hammer, flint at once
SIM.PutInBags(40772, 1); SIM.PutInBags(5956, 1)
SIM.log[#SIM.log + 1] = "with army knife: kept " .. names(ns.ToolReserve())
