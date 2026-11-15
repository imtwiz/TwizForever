-- TwizCraft craft orders: ask a friend to craft (trade them the mats), crafter crafts and trades back.
-- Both sides are played in one sim by replaying each side's party messages to the other.
SIM.sent, SIM.inGroup, SIM.partyNames = {}, true, { "Bob" }
C_ChatInfo = C_ChatInfo or {}
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ChatInfo.SendAddonMessage = function(p, m) if p == "TWZC" then SIM.sent[#SIM.sent + 1] = m end end
IsInGroup = function() return SIM.inGroup end
UnitInParty = function() return true end
local realUN = UnitName
SIM.me = "Alan"
UnitName = function(u)
    if u == "player" then return SIM.me end
    if u == "NPC" then return SIM.tradePartner end
    local i = u and tonumber(u:match("^party(%d)$") or "") if i then return SIM.partyNames[i] end return realUN(u)
end
UnitExists = function(u) return u == "player" or (u and u:match("^party%d$") and SIM.partyNames[tonumber(u:match("%d"))] ~= nil) end
UnitIsConnected = function() return true end
SIM.near = true
CheckInteractDistance = function() return SIM.near end
local L = function(s) SIM.log[#SIM.log + 1] = s end
SIM.tradeSlots, SIM.cursor = {}, nil
function InitiateTrade(unit) L("InitiateTrade " .. unit); SIM.tradeAsked = unit end
function ClearCursor() SIM.cursor = nil end
C_Container.PickupContainerItem = function(bag, slot) local s = SIM.bags[bag .. ":" .. slot] SIM.cursor = { id = s.id, n = s.count } end
C_Container.SplitContainerItem = function(bag, slot, n) local s = SIM.bags[bag .. ":" .. slot] SIM.cursor = { id = s.id, n = n } end
function ClickTradeButton(i) SIM.tradeSlots[i] = SIM.cursor; SIM.cursor = nil end
function CancelTrade() L("CancelTrade") end
local f = io.open(REPO .. "/tools/wowsim/planmake.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("local plan, why") - 1)
assert(loadstring(src))()
local NS = TwizCraft
SIM.items[2447] = { name = "Peacebloom", vendor = 1, classID = 7, subID = 9 }
SIM.items[765] = { name = "Silverleaf", vendor = 1, classID = 7, subID = 9 }
SIM.items[118] = { name = "Minor Healing Potion", vendor = 5, classID = 0 }
SIM.items[9999] = { name = "Soulbound Trinket", vendor = 5, classID = 4, bind = 1 }
local function slots() local t = {} for i = 1, 6 do local s = SIM.tradeSlots[i] if s then t[#t + 1] = i .. ":" .. SIM.items[s.id].name .. "x" .. s.n end end return table.concat(t, " ") end

-- ===== Alan asks Bob (Bob's Alchemy synced into Alan's friends) =====
SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.Advance(2)
for _, m in ipairs({ "B|2", "P|171|60|150|Alchemy", "R|171|2330:118:1:2447*1/765*1,9001:9999:1:2447*1", "E" }) do
    SIM.Fire("CHAT_MSG_ADDON", "TWZC", m, "PARTY", "Bob-Realm")
end
SIM.Advance(1)
SIM.PutInBags(2447, 5); SIM.PutInBags(765, 3)
NS.TogglePartyCrafters(); SIM.Advance(0.2)
local potionRow, trinketRow
for _, r in ipairs(NS._partyRows()) do if r.kind == "recipe" and r.out == 118 then potionRow = r end if r.kind == "recipe" and r.out == 9999 then trinketRow = r end end
NS._partyOpen["Bob:171"] = true
for _, r in ipairs(NS._partyRows()) do if r.kind == "recipe" and r.out == 118 then potionRow = r end if r.kind == "recipe" and r.out == 9999 then trinketRow = r end end
local n0 = #SIM.log
NS.OpenCraftRequest(trinketRow)
L("BoP request -> " .. (SIM.log[n0 + 1] or "?"))
NS.OpenCraftRequest(potionRow); SIM.Advance(0.6)
local p = TwizCraftOrderFrame
p.plus:Click(); p.plus:Click(); SIM.Advance(0.6)
L("panel: " .. p.title:GetText() .. " | " .. p.what:GetText() .. " | " .. p.main:GetText() .. " enabled=" .. tostring(p.main.__enabled))
SIM.sent = {}
p.main:Click(); SIM.Advance(0.3)
L("sent: " .. table.concat(SIM.sent, " ; "))
local orderMsg = SIM.sent[#SIM.sent]
-- Bob accepts the trade request: the trade window opens on Alan's side
SIM.tradePartner = "Bob"; SIM.Fire("TRADE_SHOW"); SIM.Advance(2)
L("trade slots: " .. slots())
-- first try fails (Bob closes the window)
SIM.Fire("TRADE_CLOSED"); SIM.Advance(1)
L("after cancel: main=" .. p.main:GetText() .. " enabled=" .. tostring(p.main.__enabled) .. " sent=" .. SIM.sent[#SIM.sent])
-- Alan clicks again; this time both accept
SIM.sent = {}; SIM.tradeSlots = {}
p.main:Click(); SIM.Advance(0.3)
SIM.Fire("TRADE_SHOW"); SIM.Advance(2)
SIM.Fire("TRADE_ACCEPT_UPDATE", 1, 1); SIM.Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE or "Trade complete."); SIM.Fire("TRADE_CLOSED"); SIM.Advance(1)
L("after trade: " .. p.status:GetText() .. " | sent " .. table.concat(SIM.sent, " ; "))
local secondOrder = nil
for _, m in ipairs(SIM.sent) do end

-- ===== now play Bob: he receives Alan's order =====
-- (reset the sim's view: Bob is "me", Alan is party1; Bob knows the potion)
SIM.me, SIM.partyNames = "Bob", { "Alan" }
NS.Char().profs[171] = { name = "Alchemy", line = 171, count = 1, recipes = { [2330] = { name = "Minor Healing Potion", out = 118, made = 1, learned = true,
    reagents = { { id = 2447, qty = 1 }, { id = 765, qty = 1 } } } } }
local q = orderMsg:gsub("^Q|Bob|", "Q|Bob|")
SIM.Fire("CHAT_MSG_ADDON", "TWZC", q, "PARTY", "Alan-Realm"); SIM.Advance(0.6)
L("Bob's panel: " .. p.title:GetText() .. " | " .. p.what:GetText() .. " | " .. p.main:GetText())
SIM.tradePartner = "Alan"; SIM.Fire("TRADE_SHOW"); SIM.Advance(0.5)
SIM.Fire("TRADE_ACCEPT_UPDATE", 1, 1); SIM.Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE or "Trade complete."); SIM.Fire("TRADE_CLOSED"); SIM.Advance(1)
L("Bob after mats: " .. p.main:GetText())
local crafted = false
NS.CraftRecipeNow = function(line, id, r, n) crafted = n; SIM.PutInBags(118, n) end
p.main:Click(); SIM.Advance(1)
L("Bob crafted " .. tostring(crafted) .. " -> " .. p.main:GetText())
SIM.tradeSlots, SIM.sent = {}, {}
p.main:Click(); SIM.Advance(0.3)
SIM.Fire("TRADE_SHOW"); SIM.Advance(1)
L("Bob's trade slots: " .. slots())
SIM.Fire("TRADE_ACCEPT_UPDATE", 1, 1); SIM.Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE or "Trade complete."); SIM.Fire("TRADE_CLOSED"); SIM.Advance(1)
L("Bob done: sent " .. table.concat(SIM.sent, " ; ") .. " panel shown=" .. tostring(p.__shown))
