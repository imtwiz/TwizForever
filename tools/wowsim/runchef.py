import os, sys, lupa.luajit21 as lj
HERE = os.path.dirname(os.path.abspath(__file__)); REPO = os.path.dirname(os.path.dirname(HERE))
L = lj.LuaRuntime(unpack_returned_tuples=True); g = L.globals(); g.REPO = REPO
L.execute('dofile(%r)' % os.path.join(HERE, "wowmock.lua"))
L.execute('dofile(%r)' % os.path.join(HERE, sys.argv[1]))
for l in g.SIM.log.values(): print("LOG:", l)
for c in g.SIM.calls.values():
    c = list(c.values())
    if c[0] in ("BuyMerchantItem", "CraftRecipe", "OpenTradeSkill"): print("CALL:", c)
errs = list(g.SIM.errors.values()); print("errors:", len(errs))
for e in errs[:4]: print(e[:900])
