TwizQuest 1.4.0 - which quests to do, in what order, for the most XP/hour

NEW IN 1.6.0
- Shortcut is now /tq (/qr still works). /tq help lists everything.
- Minimap button: left-click shows/hides the window, right-click replans,
  drag it around the minimap. Hover shows your planned xp/hr and next quest.
  /tq minimap hides or shows it.

NEW IN 1.5.3
- Share All button (title bar, or /tq shareall): offers every shareable quest
  in your log to your party, one every 0.5 seconds.
- Drop All button (or /tq dropall): abandons every quest in your log after a
  confirmation - it warns you if any are complete and ready to turn in.
  To drop only quests not worth doing, use /tq cleanup.

NEW IN 1.5.2
- Party XP bars: under the party line, a bar for you and each friend running
  TwizQuest - level, % through the level, XP to go, rested XP (blue), and
  roughly how long until they level at their plan's pace. Bars use class
  colors. Chat tells you when a friend levels. /tq party xp to hide them.

NEW IN 1.5.1
- Requires TomTom (the waypoint arrow for each step).

NEW IN 1.5 - PARTY SYNC
Party members who also run TwizQuest share quest logs and objective progress
automatically (hidden addon messages, only what changed).
- Party line under the summary: who's syncing, quests to share, who's behind,
  quests everyone can turn in together, quests they have that you don't.
  Hover it for details and where each friend is heading next.
- Share button (or /tq share) offers your quests they don't have. New members
  get them offered automatically once (/tq party share to toggle).
- Your route stays at a kill spot while a friend still needs kills or drops on
  a quest you've finished: "Kill 5 Kobold Vermin (helping Bob)". Shared credit
  means it costs you little and keeps you together (/tq party help to toggle).
- Quests your party shares are favoured when planning, so you quest together.
- /tq party shows status; /tq party off turns syncing off.

NEW IN 1.4
  Rested XP    - kills are worth double while you're rested, so the route
                 favors kill-heavy quests until your rested XP runs out (each
                 step shows its rested bonus; the header shows your pool).
  Target key   - one key targets step 1's mob or quest NPC. Bind it: Options >
                 Keybindings > AddOns > TwizQuest. There's also a key for
                 "waypoint to step 1".
  Groups       - in a party, elite quests are planned automatically and
                 elites are counted as about twice as fast.
  Sell & repair- bags nearly full (2 slots) or gear at 25%? A stop at the
                 nearest friendly vendor/repairer is added where it costs the
                 least time (/tq service to turn off).
  Cleanup      - quests in your log earning under a third of your plan's
                 XP/hour (gray ones included) are listed: /tq cleanup, and
                 /tq abandon drops them (asks first).

Needs Questie and TomTom (you have both) - TomTom draws the arrow to each step.

What it does
  It keeps itself up to date: a full re-plan whenever your quest log,
  level or zone changes (at most every 6s, at least every 2 min), a quick
  re-order every 60 yards you move, and finished steps vanish instantly.
  Each plan, from where you're standing:
   1. Finds every quest you can pick up right now (Questie's "is it doable"
      check, your level, not gray, not a dungeon/raid/group/elite quest),
      plus everything already in your log.
   2. For each one it finds the quest giver nearest you, the best hunting
      area for each objective (the densest cluster of spawns, favoring
      closer ones), and the turn-in nearest where you'll finish.
   3. Estimates time: travel (your real speed, mounted if you ride) +
      kills (your real seconds per kill, adjusted for mob level, drop
      rates from Questie's drop data) + rest time between pulls.
   4. Estimates XP: quest reward plus the kill XP you'll earn on the way.
   5. Builds the order of pick-ups, objectives and turn-ins that gives the
      most XP per hour over the next 60 minutes, grouping stops that are
      near each other, then polishes the order.
  Step 1 gets a TomTom arrow automatically. Click any step for its arrow.
  Hover a step for travel time, work time and XP.

Your bank
  Open your bank once (and it re-checks every time you visit). It
  remembers what's in it and where the bank is. Quest items in the bank
  count toward your objectives: the route adds a "Bank: get 3 Bear Claw"
  stop and only plans kills for what's still missing. Quests started by
  an item in your bags or bank show up as pick-ups too. Banks you haven't
  visited are found from Questie's banker list.

How it gets smarter
  There's no internet in WoW, so it can't ask an AI while you play.
  Instead it learns from you: seconds per kill, rest time per kill, run
  and mount speed, and how this server's kill and quest XP compare with
  the standard numbers. /tq learned shows what it knows. Estimates for
  new quests assume 8 kills/items or 5 objects until you accept them.

Commands (/tq or /questroute)
  /tq            show/hide the window
  /tq plan       re-plan now (normally not needed)
  /tq auto       automatic updates on/off
  /tq next       arrow to step 1
  /tq time 60    minutes to plan ahead
  /tq above 3    max levels above you
  /tq range 3000 max yards to a quest giver
  /tq elites     include elite quests
  /tq way        auto-arrow on/off
  /tq learned    what it has learned
  /tq relearn    reset learning
