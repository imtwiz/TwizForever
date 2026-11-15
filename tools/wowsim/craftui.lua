-- TwizCraft window after the clean redesign: dump what's drawn
dofile(REPO .. "/tools/wowsim/planmake.lua")
local f = TwizCraftFrame
f:Show(); TwizCraft.db.shown = true; TwizCraft.Replan(true); SIM.Advance(1)
local L = function(s) SIM.log[#SIM.log + 1] = s end
L("h=" .. f:GetHeight())
L("summary: " .. (f.summary:GetText() or "") .. "   sub: " .. (f.sub:GetText() or "") .. "  bar=" .. tostring(f.bar.__shown))
L("labels: " .. (f.stepTitle:GetText() or "") .. " / " .. (f.nowTitle.__shown and f.nowTitle:GetText() or "-") .. " / " .. (f.shopTitle:GetText() or "") .. " " .. (f.shopNote:GetText() or "") .. " / " .. (f.routeTitle.__shown and f.routeTitle:GetText() or "-"))
L("buy shown=" .. tostring(f.buyBtn.__shown) .. " party shown=" .. tostring(f.partyBtn.__shown))
AuctionHouseFrame.__shown = true; TwizCraft.ahOpen = true; TwizCraft.RefreshUI(); SIM.Advance(0.5)
L("at AH: buy=" .. (f.buyBtn:GetText() or "") .. " h=" .. f:GetHeight())
