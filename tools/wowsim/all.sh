#!/bin/sh
# Runs every scenario with plain LuaJIT and says which ones fail.
#   sh tools/wowsim/all.sh
# Each run is limited to 2 GB of memory and 90 seconds, so a runaway
# scenario stops instead of taking the computer down with it.
here=$(dirname "$0")
# realcraft.lua needs real saved data, so it is not part of this list
scenarios="scenario postall paging tools vendorbuy quest accept party partynames groupplan pickup autogroup dropall minimap planmake craftall craftmail craftparty openwin chef"
failed=0
for name in $scenarios; do
    result=$( (ulimit -v 2000000; timeout 90 luajit "$here/sim.lua" "$name.lua" 2>&1) | grep '^errors:' )
    if [ "$result" = "errors: 0" ]; then
        echo "ok    $name"
    else
        echo "FAIL  $name  (${result:-did not finish}): luajit $here/sim.lua $name.lua"
        failed=1
    fi
done
exit $failed
