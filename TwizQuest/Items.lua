-- TwizQuest items (1.21.0)
--  * Quest item button: when the current step's quest has an item you use (Questie/the quest log
--    calls it a "special" item), it sits in a button beside the TwizQuest window and on a key
--    (Options > Keybindings > AddOns > TwizQuest: "Use step 1's quest item").
--  * Best reward: on a reward screen with a choice, TwizQuest names the best one - a real upgrade
--    for your class if there is one, else the one that sells for the most - and Space takes it.
local ADDON, NS = ...
-- This client's global GetItemInfo can error ("attempt to call a nil value"); use the C_Item
-- versions when the game has them (looked up on each call)
local function GetItemInfo(x)
    local f = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    if not (f and x) then return nil end
    return f(x)
end
local function GetItemCount(x)
    local f = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
    return f and x and f(x) or 0
end

------------------------------------------------------------------------
-- quest item button
------------------------------------------------------------------------
local itemBtn, itemDirty

local function SpecialItem(questID)
    if not questID or questID <= 0 then return nil end
    local idx = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
    if not idx or not GetQuestLogSpecialItemInfo then return nil end
    local link, icon = GetQuestLogSpecialItemInfo(idx)
    if link then return link, icon end
end
NS.SpecialItem = SpecialItem

local function MakeItemButton()
    itemBtn = CreateFrame("Button", "TwizQuestItemButton", UIParent, "SecureActionButtonTemplate")
    itemBtn:RegisterForClicks("AnyUp", "AnyDown")
    itemBtn:SetAttribute("type", "item")
    itemBtn:SetSize(36, 36)
    itemBtn.icon = itemBtn:CreateTexture(nil, "ARTWORK"); itemBtn.icon:SetAllPoints()
    itemBtn:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if GameTooltip.SetHyperlink then pcall(GameTooltip.SetHyperlink, GameTooltip, self.link) end
        GameTooltip:AddLine("TwizQuest: use this for step 1 (bind a key in Options > Keybindings > AddOns > TwizQuest)", 0.4, 0.8, 1, true)
        GameTooltip:Show()
    end)
    itemBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    itemBtn:Hide()
end

function NS.UpdateItemButton()
    if not itemBtn then MakeItemButton() end
    if InCombatLockdown() then itemDirty = true; return end
    itemDirty = false
    local plan = NS._plan and NS._plan()
    local link, icon
    -- the first of the next three steps whose quest has a usable item
    for i = 1, 3 do
        local s = plan and plan.route[i]
        if s and s.q and s.q.id then link, icon = SpecialItem(s.q.id) end
        if link then break end
    end
    itemBtn.link = link
    itemBtn:SetAttribute("item", link)
    if link then
        itemBtn.icon:SetTexture(icon)
        local anchor = _G.TwizQuestFrame
        itemBtn:ClearAllPoints()
        if anchor and anchor:IsShown() then itemBtn:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, -4)
        else itemBtn:SetPoint("CENTER", UIParent, "CENTER", 0, -180) end
        itemBtn:Show()
    else
        itemBtn:Hide()
    end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE" }) do ev:RegisterEvent(e) end
local queued
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" and not itemDirty then return end
    if queued then return end
    queued = true
    C_Timer.After(0.3, function() queued = false; pcall(NS.UpdateItemButton) end)
end)

------------------------------------------------------------------------
-- best quest reward
------------------------------------------------------------------------
-- armor you can wear, by class (mail/plate come at 40)
local ARMOR = {
    WARRIOR = { "Cloth", "Leather", "Mail", Plate = 40 }, PALADIN = { "Cloth", "Leather", "Mail", Plate = 40 },
    HUNTER = { "Cloth", "Leather", Mail = 40 }, SHAMAN = { "Cloth", "Leather", Mail = 40 },
    ROGUE = { "Cloth", "Leather" }, DRUID = { "Cloth", "Leather" },
    PRIEST = { "Cloth" }, MAGE = { "Cloth" }, WARLOCK = { "Cloth" },
}
local BEST_ARMOR = { -- the heaviest you can wear counts as an upgrade; lighter ones don't
    WARRIOR = { "Mail", Plate = 40 }, PALADIN = { "Mail", Plate = 40 }, HUNTER = { "Leather", Mail = 40 },
    SHAMAN = { "Leather", Mail = 40 }, ROGUE = { "Leather" }, DRUID = { "Leather" },
    PRIEST = { "Cloth" }, MAGE = { "Cloth" }, WARLOCK = { "Cloth" },
}
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}

local function Wears(list, sub, lvl)
    for k, v in pairs(list or {}) do
        if type(k) == "number" and v == sub then return true end
        if type(k) == "string" and k == sub and lvl >= v then return true end
    end
    return false
end

local function EquippedLevel(slots)
    local low
    for _, slot in ipairs(slots) do
        local link = GetInventoryItemLink("player", slot)
        local il = link and select(4, GetItemInfo(link)) or 0
        if not low or il < low then low = il end
    end
    return low or 0
end

-- index of the best choice, and why ("upgrade" / "sells best")
function NS.BestReward()
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if n < 2 then return n == 1 and 1 or nil end
    local _, class = UnitClass("player")
    local lvl = UnitLevel("player") or 1
    local best, bestScore, why = 1, -1, "sells best"
    for i = 1, n do
        local link = GetQuestItemLink and GetQuestItemLink("choice", i)
        local name, _, _, ilvl, minLvl, itype, sub, _, equipLoc, _, sell = GetItemInfo(link or "")
        local score = sell or 0
        local up = false
        local slots = equipLoc and SLOTS[equipLoc]
        if name and slots and (minLvl or 0) <= lvl + 1 then
            local wearable = itype ~= "Armor" or sub == "Miscellaneous" or equipLoc == "INVTYPE_CLOAK"
                or (Wears(BEST_ARMOR[class], sub, lvl) or (Wears(ARMOR[class], sub, lvl) and not BEST_ARMOR[class]))
            if itype == "Weapon" and IsEquippableItem and not IsEquippableItem(link) then wearable = false end
            if wearable then
                local gain = (ilvl or 0) - EquippedLevel(slots)
                if gain > 0 then up = true; score = 1e7 + gain * 1e4 + (sell or 0) end
            end
        end
        if score > bestScore then best, bestScore, why = i, score, up and "upgrade" or "sells best" end
    end
    return best, why
end

local rewardEv = CreateFrame("Frame")
rewardEv:RegisterEvent("QUEST_COMPLETE")
rewardEv:SetScript("OnEvent", function()
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if n < 2 or not NS.db then return end
    -- item info may still be loading: look again a moment later
    C_Timer.After(0.3, function()
        local i, why = NS.BestReward()
        local link = i and GetQuestItemLink("choice", i)
        if link then NS.Print(("best reward: %s (%s) - press Space to take it, or 1-%d to pick."):format(link, why, n)) end
    end)
end)
