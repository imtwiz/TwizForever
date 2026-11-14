TwizQuest 1.4.0 - which quests to do, in what order, for the most XP/hour

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
                 least time (/qr service to turn off).
  Cleanup      - quests in your log earning under a third of your plan's
                 XP/hour (gray ones included) are listed: /qr cleanup, and
                 /qr abandon drops them (asks first).

Needs Questie (you have it). Works best with TomTom (you have it) for the arrow.

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
  the standard numbers. /qr learned shows what it knows. Estimates for
  new quests assume 8 kills/items or 5 objects until you accept them.

Commands (/qr or /questroute)
  /qr            show/hide the window
  /qr plan       re-plan now (normally not needed)
  /qr auto       automatic updates on/off
  /qr next       arrow to step 1
  /qr time 60    minutes to plan ahead
  /qr above 3    max levels above you
  /qr range 3000 max yards to a quest giver
  /qr elites     include elite quests
  /qr way        auto-arrow on/off
  /qr learned    what it has learned
  /qr relearn    reset learning
