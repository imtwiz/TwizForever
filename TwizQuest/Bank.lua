-- TwizQuest bank memory: what's in your bank and where your banks are.
-- The game only shows bank contents while the bank is open, so we remember
-- them every time you open it (per character).
local ADDON, NS = ...

local f = CreateFrame("Frame")
local bankOpen = false

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function Store()
    local db = NS.db
    db.bank = db.bank or {}
    local k = CharKey()
    db.bank[k] = db.bank[k] or { items = {}, spots = {} }
    return db.bank[k]
end

local function BankBags()
    local list = { BANK_CONTAINER or -1 }
    local first = (NUM_BAG_SLOTS or 4) + 1
    local count = NUM_BANKBAGSLOTS or 7
    for b = first, first + count - 1 do list[#list + 1] = b end
    if REAGENTBANK_CONTAINER then list[#list + 1] = REAGENTBANK_CONTAINER end
    return list
end

local function ScanBank()
    if not bankOpen or not NS.db then return end
    local items, any = {}, false
    for _, bag in ipairs(BankBags()) do
        local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
        if ok and n and n > 0 then
            any = true
            for slot = 1, n do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local id = info and NS.safe(info.itemID)
                if id then items[id] = (items[id] or 0) + (NS.safe(info.stackCount) or 1) end
            end
        end
    end
    if not any then return end
    local s = Store()
    s.items, s.at = items, time()
    if NS.MarkDirty then NS.MarkDirty() end
end

-- Remember where you stood when the bank opened: that's a bank.
local function RememberSpot()
    if not NS.Bridge() then return end
    local x, y, inst = NS.PlayerPos()
    if not x then return end
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return end
    local mx, my = pos:GetXY()
    local s = Store()
    for _, sp in ipairs(s.spots) do
        if sp.inst == inst and NS.Dist(sp.x, sp.y, x, y) < 60 then return end
    end
    table.insert(s.spots, { x = x, y = y, inst = inst, map = map, mx = mx * 100, my = my * 100 })
end

f:RegisterEvent("BANKFRAME_OPENED")
f:RegisterEvent("BANKFRAME_CLOSED")
f:RegisterEvent("BAG_UPDATE_DELAYED")
pcall(f.RegisterEvent, f, "PLAYERBANKSLOTS_CHANGED")
pcall(f.RegisterEvent, f, "PLAYERREAGENTBANKSLOTS_CHANGED")
f:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
        bankOpen = true
        pcall(RememberSpot)
        C_Timer.After(0.3, ScanBank)
    elseif event == "BANKFRAME_CLOSED" then
        ScanBank()
        bankOpen = false
    elseif bankOpen then
        ScanBank()
    end
end)

-- How many of an item are sitting in your bank.
function NS.BankCount(itemID)
    if not NS.db or not itemID then return 0 end
    local s = NS.db.bank and NS.db.bank[CharKey()]
    local n = s and s.items[itemID] or 0
    -- some clients also report bank counts while it's closed; use whichever is higher
    if C_Item and C_Item.GetItemCount then
        local okA, all = pcall(C_Item.GetItemCount, itemID, true)
        local okB, bags = pcall(C_Item.GetItemCount, itemID, false)
        if okA and okB and all and bags and all - bags > n then n = all - bags end
    end
    return n
end

function NS.BagCount(itemID)
    local get = (C_Item and C_Item.GetItemCount) or GetItemCount
    local ok, n = pcall(get, itemID)
    return ok and n or 0
end

function NS.BankKnown()
    local s = NS.db and NS.db.bank and NS.db.bank[CharKey()]
    return s and s.at
end

-- Bankers from Questie's database, by continent. Built once by the planner
-- (it may pause between frames), then looked up instantly.
local bankers
function NS.PrepareBankers()
    if not bankers then
        bankers = {}
        local B = NS.Bridge()
        local flag = B and B.DB.npcFlags and B.DB.npcFlags.BANKER
        if flag and B.DB.NPCPointers then
            local faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
            local band = bit and bit.band
            local n = 0
            for npc in pairs(B.DB.NPCPointers) do
                n = n + 1
                if n % 300 == 0 and NS.Yield then NS.Yield() end
                local flags = NS.N(npc, "npcFlags")
                if flags and band and band(flags, flag) ~= 0 then
                    local fr = NS.N(npc, "friendlyToFaction")
                    if fr and fr:find(faction, 1, true) then
                        local spawns = NS.N(npc, "spawns")
                        for areaId, list in pairs(type(spawns) == "table" and spawns or {}) do
                            for _, c in ipairs(type(list) == "table" and list or {}) do
                                local wx, wy, i, map
                                if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and c[1] > 0 then
                                    wx, wy, i, map = NS.World(areaId, c[1], c[2])
                                end
                                if wx then
                                    bankers[i] = bankers[i] or {}
                                    table.insert(bankers[i], { x = wx, y = wy, map = map, mx = c[1], my = c[2] })
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Nearest bank to (rx, ry) on this continent: ones you've used, or Questie's bankers.
function NS.NearestBank(inst, rx, ry)
    local best, bd
    local s = NS.db.bank and NS.db.bank[CharKey()]
    for _, sp in ipairs(s and s.spots or {}) do
        if sp.inst == inst then
            local d = NS.Dist(sp.x, sp.y, rx, ry)
            if not bd or d < bd then best, bd = sp, d end
        end
    end
    for _, sp in ipairs(bankers and bankers[inst] or {}) do
        local d = NS.Dist(sp.x, sp.y, rx, ry)
        if not bd or d < bd then best, bd = sp, d end
    end
    return best
end
