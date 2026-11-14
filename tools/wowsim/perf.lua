-- Performance scenario: a realistic-size AH (6000 items, ~60k listings), full scan twice,
-- count UI refreshes and measure CPU per phase.
local ADDON_DIR = ADDON_DIR
math.randomseed(42)
for id = 100000, 105999 do
    SIM.items[id] = { name = "Item " .. id, vendor = math.random(1, 500), classID = (id % 3 == 0) and 2 or 7, subID = id % 13, quality = 1, uncached = (id % 4 == 0), gear = (id % 3 == 0) }
    local ls = {}
    local base = math.random(10, 50000)
    for k = 1, math.random(1, 20) do
        ls[#ls + 1] = { unit = math.floor(base * (0.4 + math.random())), qty = (id % 3 == 0) and 1 or math.random(1, 40), timeLeft = math.random(0, 3),
                        minBid = (id % 3 == 0 and math.random() < 0.3) and math.floor(base * 0.2) or nil }
    end
    SIM.ah[id] = { commodity = (id % 3 ~= 0), listings = ls }
end
for i = 1, 60 do SIM.PutInBags(100000 + i * 7, 5) end

local ns = SIM.LoadAddon(ADDON_DIR, "DepositWise")
SIM.Fire("ADDON_LOADED", "DepositWise")
SIM.Fire("PLAYER_LOGIN")
SIM.Advance(1)

-- count refreshes
local refreshes, refreshCPU = 0, 0
local orig = ns.UI.Refresh
ns.UI.Refresh = function(...) refreshes = refreshes + 1 local t = os.clock() orig(...) refreshCPU = refreshCPU + (os.clock() - t) end

local function phase(label, f)
    local r0, c0, t0 = refreshes, refreshCPU, os.clock()
    f()
    PERF[#PERF + 1] = ("%-28s cpu %.3fs  refreshes %5d (%.3fs)"):format(label, os.clock() - t0, refreshes - r0, refreshCPU - c0)
end
PERF = {}
AuctionHouseFrame.__shown = true
phase("open AH + bag scan", function() SIM.Fire("AUCTION_HOUSE_SHOW") SIM.Advance(40) end)
ns.UI.SetTab("DEALS")
phase("full scan 1 (deals tab)", function() SlashCmdList.DEPOSITWISE("fullscan") SIM.Advance(60) end)
for id, a in pairs(SIM.ah) do if a.listings[1] then a.listings[1].qty = math.max(0, a.listings[1].qty - 1) end end
SIM.now = SIM.now + 1200 SIM.gt = SIM.gt + 1200
ns.UI.SetTab("BRIEF")
phase("full scan 2 (briefing tab)", function() SlashCmdList.DEPOSITWISE("fullscan") SIM.Advance(60) end)
phase("visit tabs", function() for _, k in ipairs({ "BRIEF", "BAGS", "DEALS", "MOVERS", "SMELT", "CRAFT", "SESSION" }) do ns.UI.SetTab(k) ns.UI.Refresh() end end)
phase("30 bag updates (craft tab)", function() ns.UI.SetTab("CRAFT") for i = 1, 30 do SIM.Fire("BAG_UPDATE_DELAYED") SIM.Advance(0.1) end end)
phase("logout", function() SIM.Fire("PLAYER_LOGOUT") end)
-- saved variable size estimate
local function size(v) local t = type(v) if t == "table" then local s = 2 for k, x in pairs(v) do s = s + size(k) + size(x) + 6 end return s elseif t == "string" then return #v + 2 else return #tostring(v) end end
local parts = {}
for k, v in pairs(DepositWiseDB) do parts[#parts + 1] = ("%s=%.0fKB"):format(k, size(v) / 1024) end
table.sort(parts)
PERF[#PERF + 1] = "SV: " .. table.concat(parts, " ")
