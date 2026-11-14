-- TwizAH: more bag items than fit -> Prev/Next pages reach every item
ADDON_DIR = REPO .. "/TwizAH"
dofile(REPO .. "/tools/wowsim/scenario.lua")
local ns = TwizAH or DepositWise
local UI = ns and ns.UI
if not (UI and UI._frame) then for k, v in pairs(_G) do if type(v) == "table" and rawget(v, "UI") and rawget(v, "items") then ns = v; UI = v.UI end end end
local base = ns.items
local real = #base
local many = {}
for i = 1, 60 do many[i] = base[((i - 1) % real) + 1] end
ns.items = many
local f = UI._frame()
f:SetHeight(560); f:Show()
UI.SetTab("BAGS"); SIM.Advance(1)
local function seen()
    local n = 0
    for _, r in ipairs(UI._rows()) do if r.__shown and r.data then n = n + 1 end end
    return n
end
local per = seen()
SIM.log[#SIM.log + 1] = ("60 items, %d rows fit, pager shown=%s, %s, prev enabled=%s"):format(per, tostring(f.pager.__shown), (f.pageText:GetText() or ""), tostring(f.pagePrev.__enabled))
local total, pages = per, 1
while f.pageNext.__enabled and pages < 20 do
    f.pageNext:Click(); SIM.Advance(1); pages = pages + 1
    total = total + seen()
    SIM.log[#SIM.log + 1] = ("  %s: %d rows"):format((f.pageText:GetText() or ""), seen())
end
SIM.log[#SIM.log + 1] = ("reached every item: %s (%d row-views for 60 items)"):format(tostring(total >= 60), total)
f.pagePrev:Click(); SIM.Advance(1)
SIM.log[#SIM.log + 1] = "after Prev: " .. (f.pageText:GetText() or "")
-- list shrinks to a few items while on a later page -> back in range, pager hides
-- go to the last page, then the list shrinks (items posted/sold): page must come back into range
for _ = 1, 30 do if not f.pageNext.__enabled then break end f.pageNext:Click(); SIM.Advance(0.2) end
ns.items = { base[1], base[2] }
UI.Refresh(); SIM.Advance(0.2)
SIM.log[#SIM.log + 1] = ("shrunk to %d items: rows %d, pager shown=%s"):format(#ns.items, seen(), tostring(f.pager.__shown))
