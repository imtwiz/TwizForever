TwizChef 1.0.0 - buys missing cooking ingredients for your best recipes

1. Open your Cooking window once (and again after learning new recipes).
   The game only shares recipes while that window is open, so TwizChef
   remembers them then. You'll see "remembered N cooking recipes".
2. Talk to any vendor. TwizChef looks at the cooking ingredients in your
   bags (meat, fish, eggs, clam meat...), finds every recipe they fit,
   and buys what's missing (spices, flour, etc.) from that vendor.

Which recipe wins when ingredients overlap (e.g. two clam meat recipes):
  - Recipes you're too low level to eat are skipped.
  - Higher level wins, but the buff matters: a buff for your main stats
    is worth up to 16 levels, and a buff your spec doesn't use (Intellect
    food for a warrior) counts 20 levels against it.
  - Recipes that are orange/yellow for skill-ups get a small edge.
  - The best recipe uses all the ingredient it can; leftovers go to the
    next best recipe.
Recipes made only from vendor ingredients are never bought for, so it
won't drain your gold on Spice Bread.

It asks before spending more than 10g in one visit, buys one purchase at
a time and stops if your bags fill up, you run out of gold, or you close
the vendor.

Commands (/chef or /autochef):
  /chef             turn on/off
  /chef plan        at a vendor: show what it would buy, without buying
  /chef buy         at a vendor: run it now
  /chef recipes     your best recipes for your current spec
  /chef spec        the stat priority it's using
  /chef stats agi sta ap   set your own priority (/chef stats auto to undo)
  /chef confirm 10  ask before spending more than 10g
  /chef max 20      cap crafts per recipe (0 = no cap)
