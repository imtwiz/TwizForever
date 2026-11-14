#!/usr/bin/env python3
"""Run TwizAH in a simulated WoW client (LuaJIT = Lua 5.1, like the game).

  pip install lupa
  python3 tools/wowsim/run.py            # end-to-end scenario
  python3 tools/wowsim/run.py --perf     # 6000-item auction house stress test
  python3 tools/wowsim/run.py --all      # load every addon in the repo together
  python3 tools/wowsim/run.py --sv path/to/WTF/.../TwizAH.lua   # with real saved data
"""
import os, sys, lupa.luajit21 as lj
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
args = sys.argv[1:]
L = lj.LuaRuntime(unpack_returned_tuples=True)
g = L.globals()
g.ADDON_DIR = os.path.join(REPO, "TwizAH")
if "--sv" in args: g.USE_REAL_SV = args[args.index("--sv") + 1]
L.execute('dofile(%r)' % os.path.join(HERE, "wowmock.lua"))
if "--all" in args:
    dirs = [d for d in sorted(os.listdir(REPO)) if os.path.exists(os.path.join(REPO, d, d + ".toc"))]
    for d in dirs: L.globals().SIM.LoadAddon(os.path.join(REPO, d), d)
    L.execute("""
      for _, d in ipairs({...}) do SIM.Fire("ADDON_LOADED", d) end
      SIM.Fire("PLAYER_LOGIN"); SIM.Fire("PLAYER_ENTERING_WORLD", true, false); SIM.Advance(5)
      AuctionHouseFrame.__shown = true; SIM.Fire("AUCTION_HOUSE_SHOW"); SIM.Advance(30)
      AuctionHouseFrame.__shown = false; SIM.Fire("AUCTION_HOUSE_CLOSED"); SIM.Advance(1)
      SIM.OpenMerchant(); SIM.Advance(5); SIM.CloseMerchant()
      MailFrame.__shown = true; SIM.Fire("MAIL_SHOW"); SIM.Advance(2); SIM.Fire("MAIL_CLOSED")
      SIM.Fire("PLAYER_LOGOUT")""".replace("{...}", "{" + ",".join('"%s"' % d for d in dirs) + "}"))
elif "--perf" in args:
    L.execute('dofile(%r)' % os.path.join(HERE, "perf.lua"))
    for p in g.PERF.values(): print(p)
else:
    L.execute('dofile(%r)' % os.path.join(HERE, "scenario.lua"))
    for line in g.SIM.log.values(): print(line)
errs = list(g.SIM.errors.values())
print("errors:", len(errs))
for e in errs[:5]: print(e[:800]); print("-" * 40)
sys.exit(1 if errs else 0)
