-- Minimal World of Warcraft API simulator for running addon code outside the game.
-- Frames are permissive stubs; game systems (AH, bags, merchant, mail, quests) are scriptable.
SIM = { now = 1794700000, money = 50000000, events = {}, frames = {}, timers = {}, log = {}, errors = {},
        calls = {}, items = {}, bags = {}, gt = 0 }

local function rec(name, ...) local t = { name, ... } SIM.calls[#SIM.calls + 1] = t end

-- ------------------------------------------------------------------ basics
function time() return SIM.now end
function GetTime() return SIM.gt end
function GetServerTime() return SIM.now end
date = os.date
function GetMoney() return SIM.money end
function print(...) local p = {} for i = 1, select("#", ...) do p[#p + 1] = tostring(select(i, ...)) end SIM.log[#SIM.log + 1] = table.concat(p, " ") end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CopyTable(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == "table" and CopyTable(v) or v end return o end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function GetMoneyString(c) c = math.floor(c) local g = math.floor(c / 10000) local s = math.floor(c / 100) % 100 local cc = c % 100
    local o = {} if g > 0 then o[#o + 1] = g .. "g" end if s > 0 then o[#o + 1] = s .. "s" end if cc > 0 or #o == 0 then o[#o + 1] = cc .. "c" end return table.concat(o, " ") end
function UnitName(u) if u == "player" then return "Twiz" end if u == "npc" then return "Test Vendor" end end
function GetRealmName() return "Forever" end
function GetZoneText() return "Stormwind" end
function InCombatLockdown() return false end
function UnitAffectingCombat() return false end
function UnitIsDeadOrGhost() return false end
function IsMounted() return false end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function GetNumLootItems() return 0 end
function GetCursorInfo() return nil end
function SpellIsTargeting() return false end
function IsFlying() return false end
function UnitOnTaxi() return false end
function IsShiftKeyDown() return SIM.shift or false end
function hooksecurefunc(a, b, c)
    if type(a) == "table" then local orig = a[b] a[b] = function(...) local r = { orig(...) } c(...) return unpack(r) end
    else local orig = _G[a] _G[a] = function(...) local r = { orig(...) } b(...) return unpack(r) end end
end
function GameTooltip_Hide() end
function geterrorhandler() return function(e) SIM.errors[#SIM.errors + 1] = e end end
YES, NO = "Yes", "No"
ITEM_QUALITY_COLORS = { [0] = { hex = "|cff9d9d9d" }, [1] = { hex = "|cffffffff" }, [2] = { hex = "|cff1eff00" }, [3] = { hex = "|cff0070dd" }, [4] = { hex = "|cffa335ee" } }
ERR_AUCTION_SOLD_S = "A buyer has been found for your auction of %s."
ERR_AUCTION_EXPIRED_S = "Your auction of %s has expired."
AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"
AUCTION_WON_MAIL_SUBJECT = "Auction won: %s"
AUCTION_OUTBID_MAIL_SUBJECT = "Outbid on %s"
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4
StaticPopupDialogs = {}
function StaticPopup_Show(name, ...) rec("StaticPopup_Show", name, ...) SIM.popup = name end
SlashCmdList = {}

-- ------------------------------------------------------------------ frames
local Stub = {}
local function NewStub(kind, name)
    local o = { __kind = kind or "Frame", __scripts = {}, __events = {}, __shown = true, __w = 100, __h = 20, __text = "", __checked = false, __enabled = true }
    return setmetatable(o, Stub)
end
Stub.__index = function(self, k)
    local m = rawget(Stub, k)
    if m then return m end
    -- unknown field: WoW methods are CamelCase; addon fields are usually lowercase -> nil
    if type(k) ~= "string" or not k:find("^%u") then return nil end
    return function(s, ...)
        if type(k) == "string" and (k:find("^Create") or k:find("^Get")) then return NewStub("Child") end
    end
end
function Stub.RegisterEvent(self, e) self.__events[e] = true SIM.frames[self] = true end
function Stub.UnregisterEvent(self, e) self.__events[e] = nil end
function Stub.UnregisterAllEvents(self) self.__events = {} end
function Stub.IsEventRegistered(self, e) return self.__events[e] or false end
function Stub.SetScript(self, s, f) self.__scripts[s] = f end
function Stub.GetScript(self, s) return self.__scripts[s] end
function Stub.HookScript(self, s, f) local o = self.__scripts[s] self.__scripts[s] = function(...) if o then o(...) end f(...) end end
function Stub.Show(self) self.__shown = true end
function Stub.Hide(self) self.__shown = false end
function Stub.SetShown(self, v) self.__shown = v and true or false end
function Stub.IsShown(self) return self.__shown end
function Stub.IsVisible(self) return self.__shown end
function Stub.SetText(self, t) self.__text = t == nil and "" or tostring(t) end
function Stub.GetText(self) return self.__text end
function Stub.SetFormattedText(self, f, ...) self.__text = f:format(...) end
function Stub.GetWidth(self) return self.__w end
function Stub.GetHeight(self) return self.__h end
function Stub.GetSize(self) return self.__w, self.__h end
function Stub.SetWidth(self, w) assert(type(w) == "number", "SetWidth needs number") self.__w = w end
function Stub.SetHeight(self, h) assert(type(h) == "number", "SetHeight needs number") self.__h = h end
function Stub.SetSize(self, w, h) assert(type(w) == "number" and type(h) == "number", "SetSize needs numbers") self.__w, self.__h = w, h end
function Stub.GetStringWidth(self) return #(self.__text or "") * 6 end
function Stub.GetStringHeight(self) return 12 end
function Stub.GetFontString(self) self.__fs = self.__fs or NewStub("FontString") return self.__fs end
function Stub.SetChecked(self, v) self.__checked = v and true or false end
function Stub.GetChecked(self) return self.__checked end
function Stub.SetEnabled(self, v) self.__enabled = v and true or false end
function Stub.IsEnabled(self) return self.__enabled end
function Stub.Enable(self) self.__enabled = true end
function Stub.Disable(self) self.__enabled = false end
function Stub.GetName(self) return self.__name end
function Stub.GetParent(self) return self.__parent end
function Stub.GetValue(self) return self.__value or 1 end
function Stub.SetValue(self, v) self.__value = v end
function Stub.GetNumPoints(self) return 1 end
function Stub.GetCenter(self) return 500, 400 end
function Stub.GetLeft(self) return 100 end
function Stub.GetTop(self) return 700 end
function Stub.GetRight(self) return 900 end
function Stub.GetBottom(self) return 100 end
function Stub.GetEffectiveScale(self) return 1 end
function Stub.GetScale(self) return 1 end
function Stub.IsMouseOver(self) return false end
function Stub.Click(self, button) local f = self.__scripts.OnClick if f then f(self, button or "LeftButton", true) end end
function Stub.IsObjectType(self, t) return self.__kind == t end
function Stub.GetObjectType(self) return self.__kind end
function Stub.GetChildren(self) return end
function Stub.GetNumLines(self) return 0 end
function Stub.SetAttribute(self, k, v) self.__attr = self.__attr or {} self.__attr[k] = v end
function Stub.GetAttribute(self, k) return self.__attr and self.__attr[k] end
function Stub.RegisterForClicks(self) end
function Stub.NumLines(self) return 0 end
function Stub.GetTextColor(self) return 1, 1, 1, 1 end
function Stub.GetFrameLevel(self) return 1 end
function Stub.GetFrameStrata(self) return "HIGH" end
function Stub.GetPoint(self) return "CENTER", UIParent, "CENTER", 0, 0 end
function Stub.GetAlpha(self) return 1 end
function Stub.GetNumChildren(self) return 0 end
function Stub.GetID(self) return 1 end
function Stub.GetVerticalScroll(self) return 0 end
function Stub.GetVerticalScrollRange(self) return 0 end
function Stub.GetMinMaxValues(self) return 0, 100 end
function Stub.GetCursorPosition(self) return 0 end
function Stub.GetNumber(self) return tonumber(self.__text) or 0 end
function Stub.IsDragging(self) return false end
function Stub.IsMovable(self) return true end
function Stub.IsResizable(self) return true end

function CreateFrame(kind, name, parent, template)
    local f = NewStub(kind, name) f.__name = name f.__parent = parent f.__template = template
    if name then _G[name] = f end
    return f
end
UIParent = CreateFrame("Frame", "UIParent")
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
GameTooltip.lines = {}
function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = tostring(t) end
function GameTooltip:AddDoubleLine(a, b) self.lines[#self.lines + 1] = tostring(a) .. " | " .. tostring(b) end
function GameTooltip:SetText(t) self.lines = { tostring(t) } end
function GameTooltip:ClearLines() self.lines = {} end
MerchantFrame = CreateFrame("Frame", "MerchantFrame") MerchantFrame.__shown = false
AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame") AuctionHouseFrame.__shown = false
AuctionHouseFrame.SearchBar = CreateFrame("Frame") AuctionHouseFrame.SearchBar.SearchBox = CreateFrame("EditBox")
MailFrame = CreateFrame("Frame", "MailFrame") MailFrame.__shown = false
InboxFrame = CreateFrame("Frame", "InboxFrame")

-- ------------------------------------------------------------------ events & timers
function SIM.Fire(event, ...)
    local list = {}
    for f in pairs(SIM.frames) do if f.__events[event] and f.__scripts.OnEvent then list[#list + 1] = f end end
    for _, f in ipairs(list) do
        local ok, err = xpcall(function(...) f.__scripts.OnEvent(f, event, ...) end, debug.traceback, ...)
        if not ok then SIM.errors[#SIM.errors + 1] = event .. ": " .. err end
    end
end
local Timer = {} Timer.__index = Timer
function Timer:Cancel() self.cancelled = true end
function Timer:IsCancelled() return self.cancelled end
C_Timer = {}
function C_Timer.After(d, f) local t = setmetatable({ at = SIM.gt + d, f = f }, Timer) SIM.timers[#SIM.timers + 1] = t end
function C_Timer.NewTimer(d, f) local t = setmetatable({ at = SIM.gt + d, f = f }, Timer) SIM.timers[#SIM.timers + 1] = t return t end
function C_Timer.NewTicker(d, f, n) local t = setmetatable({ at = SIM.gt + d, f = f, every = math.max(d, 0.001), n = n }, Timer) SIM.timers[#SIM.timers + 1] = t return t end
-- advance simulated time, running timers and OnUpdate scripts
function SIM.Advance(sec, step)
    step = step or 0.05
    local target = SIM.gt + sec
    local guard = 0
    while SIM.gt < target do
        guard = guard + 1 if guard > 200000 then error("Advance runaway") end
        SIM.gt = math.min(target, SIM.gt + step) SIM.now = SIM.now + step
        local due = {}
        for i = #SIM.timers, 1, -1 do local t = SIM.timers[i] if t.cancelled then table.remove(SIM.timers, i) elseif t.at <= SIM.gt then due[#due + 1] = t end end
        table.sort(due, function(a, b) return a.at < b.at end)
        for _, t in ipairs(due) do
            if not t.cancelled then
                local ok, err = xpcall(function() t.f(t) end, debug.traceback)
                if not ok then SIM.errors[#SIM.errors + 1] = "timer: " .. err end
                if t.every and not t.cancelled then t.at = t.at + t.every if t.n then t.n = t.n - 1 if t.n <= 0 then t.cancelled = true end end
                else t.cancelled = true end
            end
        end
        for f in pairs(SIM.frames) do
            local u = f.__scripts.OnUpdate
            if u and f.__shown then local ok, err = xpcall(function() u(f, step) end, debug.traceback) if not ok then SIM.errors[#SIM.errors + 1] = "OnUpdate: " .. err end end
        end
    end
end
-- frames that only SetScript(OnUpdate) without registering events also need ticking
local origSetScript = Stub.SetScript
function Stub.SetScript(self, s, f) origSetScript(self, s, f) if s == "OnUpdate" then SIM.frames[self] = true end end

-- ------------------------------------------------------------------ items
-- SIM.items[id] = { name, quality, vendor, classID, subID, icon }
local function I(id) return SIM.items[id] end
C_Item = {}
function C_Item.GetItemInfo(id)
    if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) end
    local it = I(id) if not it or it.uncached then return nil end
    local link = ("|cffffffff|Hitem:%d::::::::|h[%s]|h|r"):format(id, it.name)
    return it.name, link, it.quality or 1, 10, 1, "Trade Goods", "", 20, "", it.icon or 134400, it.vendor or 0, it.classID or 7, it.subID or 0
end
GetItemInfo = C_Item.GetItemInfo
function C_Item.GetItemInfoInstant(id) local it = I(id) if not it then return nil end return id, "Trade Goods", "", "", it.icon or 134400, it.classID or 7, it.subID or 0 end
function C_Item.GetItemNameByID(id) local it = I(id) return it and not it.uncached and it.name or nil end
function C_Item.GetItemIconByID(id) local it = I(id) return it and (it.icon or 134400) end
function C_Item.RequestLoadItemDataByID(id) local it = I(id) if it and it.uncached then it.uncached = nil C_Timer.After(0.2, function() SIM.Fire("GET_ITEM_INFO_RECEIVED", id, true) SIM.Fire("ITEM_DATA_LOAD_RESULT", id, true) end) end end
function C_Item.DoesItemExistByID(id) return I(id) ~= nil end
function C_Item.GetItemCount(id, bank) local n = 0 for _, s in pairs(SIM.bags) do if s.id == id then n = n + s.count end end if bank then n = n + (SIM.bank and SIM.bank[id] or 0) end return n end
GetItemCount = C_Item.GetItemCount
function C_Item.GetItemID(loc) local s = SIM.bags[loc.bag .. ":" .. loc.slot] return s and s.id end
function C_Item.DoesItemExist(loc) return SIM.bags[loc.bag .. ":" .. loc.slot] ~= nil end
function C_Item.IsBound(loc) local s = SIM.bags[loc.bag .. ":" .. loc.slot] return s and s.bound or false end
function C_Item.GetItemLink(loc) local s = SIM.bags[loc.bag .. ":" .. loc.slot] return s and select(2, C_Item.GetItemInfo(s.id)) end
function C_Item.GetStackCount(loc) local s = SIM.bags[loc.bag .. ":" .. loc.slot] return s and s.count end
Enum = {
    AuctionHouseSortOrder = { Price = 0, Name = 1, Level = 2, Bid = 3, Buyout = 4 },
    ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 },
    ItemClass = { Consumable = 0, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5, Tradegoods = 7, Recipe = 9, Questitem = 12, Miscellaneous = 15, Profession = 19 },
    AuctionHouseTimeLeftBand = { Short = 0, Medium = 1, Long = 2, VeryLong = 3 },
    AuctionStatus = { Active = 0, Sold = 1 },
    CraftingReagentType = { Basic = 1, Optional = 2, Finishing = 3 },
    BagIndex = { Backpack = 0 },
}
ItemLocation = {}
function ItemLocation:CreateFromBagAndSlot(bag, slot)
    return setmetatable({ bag = bag, slot = slot }, { __index = {
        IsValid = function(self) return SIM.bags[self.bag .. ":" .. self.slot] ~= nil end,
        GetBagAndSlot = function(self) return self.bag, self.slot end,
        IsBagAndSlot = function() return true end } })
end
C_Container = {}
function C_Container.GetContainerNumSlots(bag) return bag == 0 and 16 or (bag <= 4 and 16 or 0) end
function C_Container.GetContainerItemInfo(bag, slot)
    local s = SIM.bags[bag .. ":" .. slot] if not s then return nil end
    local name, link, q, _, _, _, _, _, _, icon, vendor = C_Item.GetItemInfo(s.id)
    return { itemID = s.id, stackCount = s.count, isBound = s.bound or false, hyperlink = link or ("item:" .. s.id), iconFileID = icon or 134400,
             quality = q or 1, isLocked = false, hasNoValue = (I(s.id) and (I(s.id).vendor or 0) == 0) or false }
end
function C_Container.UseContainerItem(bag, slot)
    rec("UseContainerItem", bag, slot)
    if MerchantFrame.__shown then local s = SIM.bags[bag .. ":" .. slot] if s then SIM.money = SIM.money + (I(s.id).vendor or 0) * s.count SIM.bags[bag .. ":" .. slot] = nil SIM.soldToVendor = (SIM.soldToVendor or 0) + 1 end end
end
function C_Container.GetContainerNumFreeSlots(bag) local n = 0 for slot = 1, C_Container.GetContainerNumSlots(bag) do if not SIM.bags[bag .. ":" .. slot] then n = n + 1 end end return n end
function C_Container.GetContainerItemID(bag, slot) local s = SIM.bags[bag .. ":" .. slot] return s and s.id end
function SIM.PutInBags(id, count, bound)
    for bag = 0, 4 do for slot = 1, 16 do local k = bag .. ":" .. slot if not SIM.bags[k] then SIM.bags[k] = { id = id, count = count, bound = bound } return bag, slot end end end
end

-- ------------------------------------------------------------------ auction house
-- SIM.ah[itemID] = { commodity = true, listings = { { unit=, qty=, owner=, timeLeft=0..3, bid=, minBid= } } }
SIM.ah = {} SIM.owned = {}
C_AuctionHouse = {}
local throttleReady = true
function C_AuctionHouse.IsThrottledMessageSystemReady() return throttleReady end
function C_AuctionHouse.MakeItemKey(id, ilvl, suffix) return { itemID = id, itemLevel = ilvl or 0, itemSuffix = suffix or 0, battlePetSpeciesID = 0 } end
function C_AuctionHouse.GetItemKeyFromItem(loc) local id = C_Item.GetItemID(loc) return C_AuctionHouse.MakeItemKey(id) end
function C_AuctionHouse.GetItemKeyInfo(key) local it = I(key.itemID) if not it then return nil end return { itemID = key.itemID, itemName = it.name, quality = it.quality or 1, iconFileID = it.icon or 1, isCommodity = SIM.ah[key.itemID] and SIM.ah[key.itemID].commodity or true } end
function C_AuctionHouse.IsSellItemValid(loc) local s = SIM.bags[loc.bag .. ":" .. loc.slot] return s and not s.bound end
function C_AuctionHouse.GetItemCommodityStatus(loc) local s = SIM.bags[loc.bag .. ":" .. loc.slot] if not s then return 0 end return (I(s.id).gear and 1) or 2 end
function C_AuctionHouse.CalculateCommodityDeposit(id, d, q) local v = (I(id) and I(id).vendor or 0) return math.max(1, math.floor(v * q * 0.05 * ({ 1, 4, 12 })[d] / 4)) end
function C_AuctionHouse.CalculateItemDeposit(loc, d, q) local s = SIM.bags[loc.bag .. ":" .. loc.slot] return C_AuctionHouse.CalculateCommodityDeposit(s.id, d, q) end
local function Sorted(id) local a = SIM.ah[id] local l = {} for _, x in ipairs(a and a.listings or {}) do l[#l + 1] = x end table.sort(l, function(x, y) return x.unit < y.unit end) return l end
function C_AuctionHouse.SendSearchQuery(key, sorts, sep)
    rec("SendSearchQuery", key.itemID)
    local id = key.itemID local a = SIM.ah[id]
    C_Timer.After(0.3, function()
        if a and not a.commodity then SIM.Fire("ITEM_SEARCH_RESULTS_UPDATED", key) else SIM.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", id) end
    end)
end
C_AuctionHouse.SendSellSearchQuery = C_AuctionHouse.SendSearchQuery
function C_AuctionHouse.GetNumCommoditySearchResults(id) return #Sorted(id) end
function C_AuctionHouse.HasFullCommoditySearchResults() return true end
function C_AuctionHouse.GetCommoditySearchResultsQuantity(id) local n = 0 for _, l in ipairs(Sorted(id)) do n = n + l.qty end return n end
function C_AuctionHouse.GetCommoditySearchResultInfo(id, i) local l = Sorted(id)[i] if not l then return nil end
    return { itemID = id, unitPrice = l.unit, quantity = l.qty, numOwnerItems = l.mine and l.qty or 0, containsOwnerItem = l.mine or false, timeLeftSeconds = 3600, auctionID = l.auctionID or i } end
function C_AuctionHouse.GetNumItemSearchResults(key) return #Sorted(key.itemID) end
function C_AuctionHouse.HasFullItemSearchResults() return true end
function C_AuctionHouse.GetItemSearchResultInfo(key, i) local l = Sorted(key.itemID)[i] if not l then return nil end
    return { itemKey = key, buyoutAmount = l.unit * l.qty, quantity = l.qty, containsOwnerItem = l.mine or false, timeLeft = l.timeLeft or 2, auctionID = l.auctionID or i, bidAmount = l.bid, minBid = l.minBid } end
-- full scan
function C_AuctionHouse.ReplicateItems()
    rec("ReplicateItems")
    SIM.rep = {}
    for id, a in pairs(SIM.ah) do for _, l in ipairs(a.listings) do SIM.rep[#SIM.rep + 1] = { id = id, l = l } end end
    if not SIM.replicateBlocked then C_Timer.After(1.5, function() SIM.Fire("REPLICATE_ITEM_LIST_UPDATE") end) end
end
function C_AuctionHouse.GetNumReplicateItems() return SIM.rep and #SIM.rep or 0 end
function C_AuctionHouse.GetReplicateItemInfo(i)
    local r = SIM.rep[i + 1] if not r then return nil end
    local it, l = I(r.id), r.l
    local buyout = l.noBuyout and 0 or l.unit * l.qty
    -- name, texture, count, quality, usable, level, levelType, minBid, minIncrement, buyout, bidAmount, highBidder, bidderFull, owner, ownerFull, saleStatus, itemID, hasAllInfo
    return it.name, it.icon, l.qty, it.quality, true, 1, "", l.minBid or 0, l.minInc or 0, buyout, l.bid or 0, false, nil, nil, nil, 0, r.id, not it.uncached
end
function C_AuctionHouse.GetReplicateItemLink(i) local r = SIM.rep[i + 1] return r and select(2, C_Item.GetItemInfo(r.id)) end
function C_AuctionHouse.GetReplicateItemTimeLeft(i) local r = SIM.rep[i + 1] return r and (r.l.timeLeft or 2) end
-- posting
function C_AuctionHouse.PostCommodity(loc, d, q, unit) rec("PostCommodity", C_Item.GetItemID(loc), d, q, unit) C_Timer.After(0.2, function() SIM.Fire("AUCTION_HOUSE_AUCTION_CREATED", 1) end) return false end
function C_AuctionHouse.PostItem(loc, d, q, bid, buyout) rec("PostItem", C_Item.GetItemID(loc), d, q, buyout) C_Timer.After(0.2, function() SIM.Fire("AUCTION_HOUSE_AUCTION_CREATED", 1) end) return false end
-- buying
function C_AuctionHouse.StartCommoditiesPurchase(id, q) rec("StartCommoditiesPurchase", id, q)
    local need, total = q, 0 for _, l in ipairs(Sorted(id)) do local t = math.min(need, l.qty) total = total + t * l.unit need = need - t if need <= 0 then break end end
    C_Timer.After(0.3, function() if need > 0 then SIM.Fire("COMMODITY_PRICE_UNAVAILABLE") else SIM.Fire("COMMODITY_PRICE_UPDATED", math.floor(total / q), total) end end) end
function C_AuctionHouse.ConfirmCommoditiesPurchase(id, q) rec("ConfirmCommoditiesPurchase", id, q) C_Timer.After(0.3, function() SIM.Fire("COMMODITY_PURCHASE_SUCCEEDED") end) end
function C_AuctionHouse.CancelCommoditiesPurchase() rec("CancelCommoditiesPurchase") end
function C_AuctionHouse.PlaceBid(id, amount) rec("PlaceBid", id, amount) end
-- owned auctions
function C_AuctionHouse.QueryOwnedAuctions() rec("QueryOwnedAuctions") C_Timer.After(0.3, function() SIM.Fire("OWNED_AUCTIONS_UPDATED") end) end
function C_AuctionHouse.GetNumOwnedAuctions() return #SIM.owned end
function C_AuctionHouse.GetOwnedAuctionInfo(i) return SIM.owned[i] end
function C_AuctionHouse.GetOwnedAuctions() return SIM.owned end
function C_AuctionHouse.CancelAuction(id) rec("CancelAuction", id) C_Timer.After(0.3, function() SIM.Fire("AUCTION_CANCELED", id) end) end
function C_AuctionHouse.GetCancelCost(id) return 0 end
function C_AuctionHouse.CanCancelAuction() return true end

-- ------------------------------------------------------------------ merchant
-- SIM.merchant = { { id=, price=, stack=, avail=-1 } }
SIM.merchant = {}
function GetMerchantNumItems() return #SIM.merchant end
function GetMerchantItemID(i) return SIM.merchant[i] and SIM.merchant[i].id end
function GetMerchantItemLink(i) local m = SIM.merchant[i] return m and select(2, C_Item.GetItemInfo(m.id)) end
function GetMerchantItemMaxStack(i) return 20 end
function GetMerchantItemInfo(i) local m = SIM.merchant[i] if not m then return nil end local it = I(m.id) return it.name, it.icon, m.price, m.stack or 1, m.avail or -1, true, true, false end
C_MerchantFrame = {}
function C_MerchantFrame.GetItemInfo(i) local m = SIM.merchant[i] if not m then return nil end local it = I(m.id)
    return { name = it.name, texture = it.icon, price = m.price, stackCount = m.stack or 1, numAvailable = m.avail or -1, isPurchasable = true, isUsable = true, hasExtendedCost = false } end
function BuyMerchantItem(i, q) local m = SIM.merchant[i] q = q or (m.stack or 1) rec("BuyMerchantItem", i, q) SIM.money = SIM.money - m.price * q / (m.stack or 1) SIM.PutInBags(m.id, q) C_Timer.After(0.2, function() SIM.Fire("BAG_UPDATE_DELAYED") end) end
function SIM.OpenMerchant() MerchantFrame.__shown = true SIM.Fire("MERCHANT_SHOW") end
function SIM.CloseMerchant() MerchantFrame.__shown = false SIM.Fire("MERCHANT_CLOSED") end

-- ------------------------------------------------------------------ mail
-- SIM.mail = { { sender, subject, money, items = { {id,count} }, invoice = { type, itemName, buyer, bid, buyout, deposit, consignment } } }
SIM.mail = {}
function GetInboxNumItems() return #SIM.mail, #SIM.mail end
function GetInboxHeaderInfo(i) local m = SIM.mail[i] if not m then return end
    return nil, nil, m.sender, m.subject, m.money or 0, 0, 30, m.items and #m.items or 0, m.read or false, false, false, false, false, m.items and #m.items or 0 end
function GetInboxInvoiceInfo(i) local m = SIM.mail[i] local v = m and m.invoice if not v then return nil end
    return v.type, v.itemName, v.buyer, v.bid, v.buyout, v.deposit, v.consignment, 0, 0, 0, v.count or 1 end
function GetInboxItem(i, a) local m = SIM.mail[i] local x = m and m.items and m.items[a] if not x then return nil end return I(x.id).name, x.id, 134400, x.count, 1, true end
function GetInboxItemLink(i, a) local m = SIM.mail[i] local x = m and m.items and m.items[a] return x and select(2, C_Item.GetItemInfo(x.id)) end
function TakeInboxMoney(i) rec("TakeInboxMoney", i) local m = SIM.mail[i] if m then SIM.money = SIM.money + (m.money or 0) m.money = 0 end C_Timer.After(0.2, function() SIM.Fire("MAIL_INBOX_UPDATE") end) end
function AutoLootMailItem(i) rec("AutoLootMailItem", i) local m = SIM.mail[i] if m then for _, x in ipairs(m.items or {}) do SIM.PutInBags(x.id, x.count) end m.items = nil if (m.money or 0) == 0 then table.remove(SIM.mail, i) end end C_Timer.After(0.2, function() SIM.Fire("MAIL_INBOX_UPDATE") end) end
function TakeInboxItem(i, a) AutoLootMailItem(i) end
function DeleteInboxItem(i) rec("DeleteInboxItem", i) table.remove(SIM.mail, i) C_Timer.After(0.2, function() SIM.Fire("MAIL_INBOX_UPDATE") end) end
function CheckInbox() C_Timer.After(0.1, function() SIM.Fire("MAIL_INBOX_UPDATE") end) end

-- ------------------------------------------------------------------ quests & trade skills
SIM.quests = {}
C_QuestLog = {}
function C_QuestLog.GetNumQuestLogEntries() return #SIM.quests end
function C_QuestLog.GetInfo(i) return SIM.quests[i] end
function C_QuestLog.GetQuestObjectives(id) for _, q in ipairs(SIM.quests) do if q.questID == id then return q.objectives end end return {} end
C_TradeSkillUI = {}
function C_TradeSkillUI.GetRecipeSchematic() return nil end
function C_TradeSkillUI.GetAllRecipeIDs() return {} end
C_Map = { GetBestMapForUnit = function() return 1453 end, GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end }
C_CurrencyInfo = { GetCoinTextureString = GetMoneyString }
Settings = { RegisterCanvasLayoutCategory = function() return { GetID = function() return 1 end } end, RegisterAddOnCategory = function() end, OpenToCategory = function() end }
function GetAddOnMetadata(a, k) return "2.x" end
C_AddOns = { GetAddOnMetadata = GetAddOnMetadata, IsAddOnLoaded = function() return false end }
function IsAddOnLoaded() return false end
TooltipDataProcessor = { AddTooltipPostCall = function(kind, f) SIM.tooltipPost = f end }
Enum.TooltipDataType = { Item = 0 }

-- ------------------------------------------------------------------ addon loader
function SIM.LoadAddon(dir, name)
    local ns = {}
    local toc = io.open(dir .. "/" .. name .. ".toc"):read("*a")
    for line in toc:gmatch("[^\r\n]+") do
        local f = line:match("^%s*([%w_%-/]+%.lua)%s*$")
        if f then
            local chunk, err = loadfile(dir .. "/" .. f)
            if not chunk then error("compile " .. f .. ": " .. err) end
            local ok, e = xpcall(function() chunk(name, ns) end, debug.traceback)
            if not ok then SIM.errors[#SIM.errors + 1] = "load " .. f .. ": " .. e end
        end
    end
    return ns
end

-- ------------------------------------------------------------------ player, auras, tooltips (TwizChef / TwizQuest)
SIM.level, SIM.class, SIM.power = 20, "MAGE", 0
SIM.auras, SIM.resting, SIM.rested, SIM.group = {}, true, 0, 1
SIM.tooltips = {} -- [itemID] = "use text"
function UnitLevel() return SIM.level end
function UnitClass() return SIM.class:lower(), SIM.class end
function UnitPowerType() return SIM.power end
function UnitFactionGroup() return "Alliance" end
function UnitXP() return 1000 end
function UnitXPMax() return 20000 end
function GetXPExhaustion() return SIM.rested > 0 and SIM.rested or nil end
function GetNumGroupMembers() return SIM.group end
function IsResting() return SIM.resting end
function UnitExists() return false end
function GetSpecialization() return 1 end
function GetBindingKey(cmd) return SIM.bindings and SIM.bindings[cmd] end
function GetInventoryItemDurability(slot) local d = SIM.durability and SIM.durability[slot] if d then return d[1], d[2] end end
function debugprofilestop() return os.clock() * 1000 end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) SIM.log[#SIM.log + 1] = m end }
C_UnitAuras = { GetAuraDataByIndex = function(unit, i) local n = SIM.auras[i] return n and { name = n } end }
C_TooltipInfo = { GetItemByID = function(id) local it = SIM.items[id] if not it then return nil end
    local lines = { { leftText = it.name } }
    if SIM.tooltips[id] then lines[#lines + 1] = { leftText = "Use: " .. SIM.tooltips[id] } end
    return { lines = lines } end }
ITEM_SPELL_TRIGGER_ONUSE = "Use:"

-- override bindings (scroll-to-post)
SIM.overrides = {}
function SetOverrideBinding(owner, prio, key, cmd) rec("SetOverrideBinding", key, cmd) SIM.overrides[key] = cmd end
function ClearOverrideBindings(owner) rec("ClearOverrideBindings") SIM.overrides = {} end
function SIM.Wheel()   -- a mouse-wheel notch outside any scrolling frame
    local cmd = SIM.overrides["MOUSEWHEELDOWN"]
    if cmd == "DEPOSITWISE_POSTALL" then TwizAH.PostAll() end
end

-- addon messaging / groups (party sync)
C_ChatInfo = C_ChatInfo or {}
C_ChatInfo.RegisterAddonMessagePrefix = C_ChatInfo.RegisterAddonMessagePrefix or function() return true end
C_ChatInfo.SendAddonMessage = C_ChatInfo.SendAddonMessage or function(p, m, c) rec("SendAddonMessage", p, m, c) end
IsInGroup = IsInGroup or function() return (SIM.group or 1) > 1 end
IsInRaid = IsInRaid or function() return false end
UnitInParty = UnitInParty or function() return false end
Ambiguate = Ambiguate or function(n) return n end

-- the minimap frame
Minimap = Minimap or CreateFrame("Frame", "Minimap", UIParent)
if Minimap.SetSize then Minimap:SetSize(140, 140) end
