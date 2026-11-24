TwizRogue 1.1.0 - one-key rogue
================================

Bind the keys in Options > Keybindings > AddOns > TwizRogue.

ATTACK (the one key)
  Out of combat it first puts poison on a weapon that has none, one weapon
  per press: the highest rank of Instant Poison (main hand) / Deadly Poison
  (off hand) in your bags, falling back to the others you carry.
  In Stealth: your opener without breaking Stealth - Ambush with a dagger in
  your main hand, else Cheap Shot (/rogue opener ambush|cheap|garrote|auto).
  Then: auto attack, and per target 3 builders -> Eviscerate. The builder is
  Mutilate once you know it and hold daggers, else Sinister Strike.
  /rogue snd puts Slice and Dice after the first builder.
  /rogue stealth: on an enemy and not stealthed, the key stealths first
  (off by default - while Stealth is on cooldown it would hold the key back).

  In combat the order is fixed: the sequence only moves on when a cast goes
  off (not enough energy = it waits), and a new target starts it over. It
  can't count combo points, so a crit that gives 2 still waits for the third
  builder.

  REACTIVES (1.1.0): Riposte (after you parry, talent) and Surprise Attack
  (after the target dodges) go off by themselves on the next press the game
  allows them; the rest of the time the game skips them. /rogue reactives
  turns that off.

INTERRUPT
  Kick; hold Shift for Gouge.

VENDOR RESTOCK
  Flash Powder (once you know Vanish) up to 10, and the poisons the vendor
  sells that you already carry, up to 10 each.

Commands: /rogue (status), /rogue opener <auto|ambush|cheap|garrote>,
/rogue stealth, /rogue poisons, /rogue snd, /rogue reactives, /rogue restock
