-- Runs one scenario with plain LuaJIT (no Python needed):
--   luajit tools/wowsim/sim.lua party.lua
-- Prints the scenario's log, then "errors: N". Exits 1 when there are errors.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local script = arg[1]
if not script then
    io.stderr:write("usage: luajit tools/wowsim/sim.lua <scenario.lua>\n")
    os.exit(2)
end
REPO = here .. "/../.."
ADDON_DIR = REPO .. "/TwizAH"
dofile(here .. "/wowmock.lua")
local ok, err = xpcall(function() dofile(here .. "/" .. script) end, debug.traceback)
if not ok then SIM.errors[#SIM.errors + 1] = "scenario: " .. tostring(err) end
-- the simulator replaces print() with one that appends to SIM.log, so write directly
local function out(text) io.stdout:write(text, "\n") end
for i = 1, #SIM.log do out("LOG: " .. tostring(SIM.log[i])) end
out("errors: " .. #SIM.errors)
for i = 1, math.min(4, #SIM.errors) do out(tostring(SIM.errors[i]):sub(1, 900)) end
os.exit(#SIM.errors == 0 and 0 or 1)
