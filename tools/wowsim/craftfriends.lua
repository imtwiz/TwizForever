-- TwizCraft: friends' search covers every profession (gathering ones too), gather tooltips,
-- /tc find over friends, and reading every crafting profession by itself
SIM.sent, SIM.inGroup, SIM.partyNames = {}, false, {}
C_ChatInfo = C_ChatInfo or {}
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ChatInfo.SendAddonMessage = function(p, m) if p == "TWZC" then SIM.sent[#SIM.sent + 1] = m end end
IsInGroup = function() return SIM.inGroup end
UnitInParty = function() return false end
local realUN = UnitName
UnitName = function(u) local i = u and tonumber(u:match("^party(%d)$") or "") if i then return SIM.partyNames[i] end return realUN(u) end
GetSpellInfo = function(id) return "Spell " .. id end
C_Spell = C_Spell or {}
C_Spell.GetSpellName = function(id) return ({ [2330] = "Minor Healing Potion", [3170] = "Weak Troll's Blood Elixir" })[id] end
local f = io.open(REPO .. "/tools/wowsim/planmake.lua"); local src = f:read("*a"); f:close()
src = src:sub(1, src:find("local plan, why") - 1)
assert(loadstring(src))()
local NS = TwizCraft
local L = function(s) SIM.log[#SIM.log + 1] = s end
SIM.items[2447] = { name = "Peacebloom", vendor = 1, classID = 7, subID = 9 }
SIM.items[2318] = { name = "Light Leather", vendor = 1, classID = 7, subID = 6 }
SIM.items[118] = { name = "Minor Healing Potion", vendor = 5, classID = 0 }
-- Bob (offline friend, synced earlier): Alchemy with recipes, Herbalism and Skinning (no recipes)
SIM.inGroup, SIM.partyNames = true, { "Bob" }
SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.Advance(2)
for _, m in ipairs({ "B|2", "P|171|60|150|Alchemy", "R|171|2330:118:1:2447*1,3170:3382:1:2447*1",
    "P|182|95|150|Herbalism", "P|393|40|75|Skinning", "E" }) do
    SIM.Fire("CHAT_MSG_ADDON", "TWZC", m, "PARTY", "Bob-Realm")
end
SIM.Advance(1)
SIM.inGroup, SIM.partyNames = false, {}
SIM.Fire("GROUP_ROSTER_UPDATE"); SIM.Advance(1)   -- Bob leaves: still saved, offline
NS.TogglePartyCrafters(); SIM.Advance(0.2)
local function rows(filter)
    local box
    for _, r in ipairs(NS._partyRows()) do end
    local o = {}
    for _, r in ipairs(NS._partyRows()) do o[#o + 1] = (r.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", "")) end
    return table.concat(o, " / ")
end
L("all: " .. rows())
NS._setPartyFilter("herb"); L("search 'herb': " .. rows())
NS._setPartyFilter("skinning"); L("search 'skinning': " .. rows())
NS._setPartyFilter("alchemy"); L("search 'alchemy': " .. rows())
NS._setPartyFilter("healing"); L("search 'healing': " .. rows())
NS._setPartyFilter("")
L("gatherers of Peacebloom: " .. table.concat(NS.PartyWithProf(NS.GatherProfFor(2447)), ", "))
L("gatherers of Light Leather: " .. table.concat(NS.PartyWithProf(NS.GatherProfFor(2318)), ", "))
local n0 = #SIM.log
SlashCmdList.CRAFTROUTE("find herbalism"); SlashCmdList.CRAFTROUTE("find healing")
for i = n0 + 1, #SIM.log do L("find> " .. SIM.log[i]) end
-- reading every crafting profession at login, without opening windows yourself
NS.Professions = function() return { { name = "Engineering", skill = 82, max = 150, line = 202 },
    { name = "Blacksmithing", skill = 30, max = 75, line = 164 }, { name = "Herbalism", skill = 50, max = 75, line = 182 } } end
local opened = {}
C_TradeSkillUI.OpenTradeSkill = function(line) opened[#opened + 1] = line; SIM.openLine = line; return true end
C_TradeSkillUI.CloseTradeSkill = function() SIM.openLine = nil end
local realCapture = NS.Capture
NS.Capture = function()
    if not SIM.openLine then return nil end
    NS.Char().profs[SIM.openLine] = { name = SIM.openLine == 164 and "Blacksmithing" or "Engineering", line = SIM.openLine,
        recipes = { [2660] = { name = "Rough Sharpening Stone", out = 2862, learned = true, reagents = {} } }, count = 1, at = time(), skill = 30 }
    return 1
end
NS.Char().profs[202].skill = 82
NS.ReadAllProfessions(); SIM.Advance(10)
L("read by itself: " .. table.concat(opened, ", ") .. " | blacksmithing recorded: " .. tostring(NS.Char().profs[164] ~= nil))
