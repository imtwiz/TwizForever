-- TwizAH: Post All works down best then marginal items, one post per press
ADDON_DIR = REPO .. "/TwizAH"
dofile(REPO .. "/tools/wowsim/scenario.lua")
local ns = TwizAH
AuctionHouseFrame.__shown = true; SIM.Fire("AUCTION_HOUSE_SHOW"); SIM.Advance(1)
ns.StartBagScan(); SIM.Advance(15)
for _, it in ipairs(ns.items) do it.posted = nil end
local q = ns.PostAllQueue()
local verdicts = {}
for _, it in ipairs(q) do verdicts[#verdicts + 1] = it.result.verdict end
SIM.log[#SIM.log + 1] = ("queue: %d items [%s]"):format(#q, table.concat(verdicts, ","))
local f = ns.UI._frame(); f:Show(); ns.UI.SetTab("BAGS"); SIM.Advance(0.5)
SIM.log[#SIM.log + 1] = "wheel bound: " .. tostring(SIM.overrides["MOUSEWHEELDOWN"])
-- spin the wheel fast: 60 notches over ~3 seconds
local presses = 0
for i = 1, 60 do
  SIM.Wheel(); presses = presses + 1; SIM.Advance(0.05)
  if StaticPopup_Visible and StaticPopup_Visible("DEPOSITWISE_CONFIRM_POST") then StaticPopupDialogs.DEPOSITWISE_CONFIRM_POST.OnAccept() end
end
local skipped = {}
for _, it in ipairs(ns.items) do if not it.posted then skipped[#skipped + 1] = (it.result and it.result.verdict or "?") end end
SIM.log[#SIM.log + 1] = ("wheel notches %d, left unposted: [%s]"):format(presses, table.concat(skipped, ","))
SIM.Advance(0.5)
SIM.log[#SIM.log + 1] = "wheel after done: " .. tostring(SIM.overrides["MOUSEWHEELDOWN"])
SIM.log[#SIM.log + 1] = "button: " .. (f.postAll:GetText() or "") .. " enabled=" .. tostring(f.postAll.__enabled)
