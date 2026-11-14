# wowsim

A small World of Warcraft API simulator for testing these addons outside the game.
It fakes frames, timers, bags, the auction house (search, full scan, posting, buying,
owned auctions), merchants, mail and the quest log, then runs the addon's real code
in LuaJIT (Lua 5.1 - the same language version WoW uses).

```
pip install lupa
python3 tools/wowsim/run.py          # TwizAH end-to-end
python3 tools/wowsim/run.py --perf   # big auction house stress test
python3 tools/wowsim/run.py --all    # every addon in the repo loaded together
```

It catches Lua errors, wrong API use and logic bugs. It can't catch problems that
only the real client shows (layout, Blizzard restrictions), so still test in game.
