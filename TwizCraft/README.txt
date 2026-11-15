TwizCraft 1.4.0 - the cheapest way to level your professions

NEW IN 1.10.1 (with LeetStick's party-sync work)
- Party crafters understand Forever surnames ("Bob Stone", "Bob-Stone",
  with or without realm), ignore your own messages and strangers, and keep
  two party members with the same first name apart.

NEW IN 1.10.0 - FRIENDS DATABASE
- Friends' professions, recipes and material counts are saved in your
  TwizCraft data, so they stay after a friend leaves your group or logs off.
  Each time you group again, it re-syncs and updates them.
- The window (Party/Friends button, /tc party) lists friends in your group
  first, then offline ones with when they last synced. Their materials count
  toward "how many can we make" (tick off "Count offline friends" to use only
  people in your group). Tooltips show how old offline counts are.
- Item tooltips say "Friends can make: Bob (Engineering)".
- /tc friends lists saved friends; /tc friends forget <name>;
  /tc friends clear removes everyone who's offline.

NEW IN 1.9.0 - PARTY MATERIALS
- Party sharing is on automatically when you group with someone running
  TwizCraft: professions, recipes (with their ingredients) and now crafting
  materials - how many of every ingredient used by anyone's recipes each of
  you holds in bags, bank and mailbox. Counts update as bags change.
- Party window (/tc party): every recipe shows how many the party can make
  with everyone's materials combined (green xN). Hover a recipe to see each
  ingredient and who has it ("you 3, Bob 5"). Tick "Only what the party has
  materials for" to list just the makeable ones.
- Your bank is counted from the game's cache - open your bank once per
  session so it's up to date.

NEW IN 1.8.2
- Party crafters: same sync fixes as TwizQuest (realm names, group changes,
  dungeon-finder groups).

NEW IN 1.8.1
- Shortcut is now /tc (/cr still works). /tc help lists everything.

NEW IN 1.8.0 - PARTY CRAFTERS
- When you group with someone who also runs TwizCraft, you swap professions,
  skill levels and known recipes automatically (hidden addon messages; only
  changes are re-sent after you open a profession window).
- Party button (top of the window) or /tc party: browse each member's
  professions and recipes, click a profession to expand it, search by name.
  Recipes you don't know are marked. Hover a recipe for the item; shift-click
  to link it in chat.
- Item tooltips show "Party can make: Bob (Engineering)".

NEW IN 1.7.3
- Craft All opens the right profession window by itself (or switches to it
  if a different one is open) and starts crafting as soon as the recipes
  load. It picks the profession that has something to make: the open one,
  then the one TwizCraft is planning, then your others. If the game won't
  start a craft right after the window opens, chat tells you and the next
  press crafts.

NEW IN 1.7.2
- Craft All no longer thinks you're still crafting after a batch ends (it
  now only waits while you're actually casting), and any error it hits is
  shown in chat instead of failing silently.

NEW IN 1.7.1
- Craft All works on the profession window you have open (not just the one
  selected in TwizCraft), and after the plan's crafts it also makes anything
  else you can that still gives skill-ups - without touching materials the
  plan needs. If only gray recipes are left it names them; shift-click Craft
  All to make those too.

NEW IN 1.7.0
- Craft All button (next to Craft next, or /tc craftall): crafts everything
  you can make right now in plan order - make-first items, then each step.
  Each press crafts a whole batch of one recipe (as many as your materials
  and the plan allow). The game needs a fresh click to start each different
  recipe, so press again - or just spin your mouse wheel while the profession
  window is open. Chat tells you when a batch is done and what's next.
  Right-click stops. Bindable in Options > Keybindings > AddOns.
  /tc wheel turns the mouse-wheel shortcut off.

NEW IN 1.6.1
- Requires TomTom (for the waypoint arrow on shopping and mailbox stops).

NEW IN 1.6.0
- Makes intermediates when that's cheaper per skill point: e.g. Coarse
  Blasting Powder from Coarse Stone for Coarse Dynamite, because making the
  powder gives skill-ups too. Counts trainer recipes you can learn along the
  way (marked [learn]); switches back to buying once the intermediate goes gray.

NEW IN 1.5.1
- Fixed vendor overbuying: buying stops once your bags hold what the list needs
  (counted live, so extra clicks or TwizChef buying first never double up).
  The button shows "Buying..." while it works.

NEW IN 1.5 - mailbox
  AH purchases go to your mailbox. The moment a purchase completes it comes
  off the "to buy" list and shows as "N in mailbox", and the route gets a
  "Mailbox: pick up" stop (your nearest mailbox once you've used it).
  Opening the mailbox reads the real inbox (mats mailed from alts count too).

Open each profession's window once (and after learning new recipes) so
TwizCraft can read your recipes. Then /tc shows, for the selected
profession, from your current skill to your cap:
  - which recipe to craft at each skill range, and about how many
  - the expected net cost (materials minus what the results sell back for)
  - a shopping list: what to buy, from where (vendor / AH / craft it /
    gather it), minus what's already in your bags and bank

How it decides
  Skill colors (orange / yellow / green / gray) come from AtlasLoot's
  profession data. The skill-up chance falls from 100% at yellow to 0% at
  gray. For every skill point it picks the recipe with the lowest
  expected cost per point, then groups them into steps.
  Reagent prices: TwizAH's AH prices, vendor prices from merchants
  you've visited (TwizAH or TwizCraft saw them), or the cost of
  crafting it yourself if that's cheaper (e.g. Light Leather from scraps,
  bolts of cloth, bars) - shown as "make first".
  Unknown recipes you can get from your trainer are used too, marked
  [learn]. Recipes that need a recipe item are not.
  It re-plans every time your skill goes up, so the list stays current.
  Things with no known price are marked "gather" with a rough cost - a
  TwizAH AH scan prices them.

Buying and the cheapest route
  Under the shopping list is the cheapest route: the fewest stops that
  get everything - your bank (items to take out), the vendors that sell
  what you need (from Questie's vendor data: friendly vendors on your
  continent, covering the most items per stop, nearest first), and the
  Auction House - ordered nearest-first from where you are. Click a stop
  for a TomTom waypoint. Then what to craft first, and anything to gather.
  At a vendor, a button buys everything on your list that vendor sells
  (asks first above 5g). At the AH, the button buys the next item: click
  once for the live price, again to confirm (the game requires a click
  per purchase; red means it's 50%+ above the last known price;
  right-click skips the item). Vendor prices you haven't seen yet are
  estimated until you visit.

Refresh
  The Refresh button (top of the window) re-reads your recipes if a
  profession window is open, then re-plans with your current bags.

Make now from your bags
  Under the steps: every recipe in this profession you can make right now
  from your bags, how many, its color, and why it is or isn't a step (in
  the plan / gray: no skill-ups / costs more per point). Click to craft.
  Materials you already own are used first in the plan, valued at what
  you'd get for selling them - so fish you caught or leather you skinned
  get used before anything is bought.

Crafting from the window
  Click a step to craft it: as many as your materials allow, up to what
  the step needs. Shift-click crafts one, right-click stops. If that
  profession's window isn't open, the first click opens it - click again
  to craft. "Make ..." stops in the route (leather from scraps, bolts of
  cloth) craft the same way. "Craft next" (top of the window) makes the
  next thing on the plan; bind it to a key in Options > Keybindings >
  AddOns > TwizCraft and just keep pressing it.

It learns
  Every yellow or green craft is compared with the predicted skill-up
  chance, and the odds adjust to what you actually get (/tc odds).

Commands (/tc - /cr and /twizcraft also work)
  /tc             show/hide
  /tc target 225  plan to this skill instead of your cap (/tc target clears)
  /tc resell      also count AH resale of what you craft (default: vendor)
  /tc odds        skill-up odds learned so far
  /tc refresh     re-read recipes (with the profession window open) and re-plan
  /tc find fish   everything known about matching recipes/ingredients, and why
                  each is or isn't in the plan
  /tc buy         at a vendor: buy everything on your list it sells
  /tc size        reset the window size (drag the corner to resize)
Hover a step for skill colors, chances and per-craft costs; click it to
open the recipe. Hover a shopping item for where to get it; click it at
the AH to search for it.
