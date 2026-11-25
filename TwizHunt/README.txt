TwizHunt 1.6.0 - one-key hunter
================================

Bind the keys in Options > Keybindings > AddOns > TwizHunt.

SHOOT (the one key)
  Out of combat it first fixes what's missing, one thing per press:
    pet dead -> Revive Pet, no pet -> Call Pet, pet under 60% -> Mend Pet,
    pet unhappy -> Feed Pet with the best food in your bags it eats,
    an enemy targeted without Aspect of the Hawk -> Aspect of the Hawk
    (/hunt cheetah: Aspect of the Cheetah when nothing's targeted).
  Then, on an enemy: Auto Shot + your pet attacks, and on each NEW target
  Hunter's Mark -> Summon Hawk -> Serpent Sting once, then Concussive Shot
  every time it's ready (1.3.0 - slows the target so it can't reach you;
  /hunt concussive turns it off), and Arcane Shot every time it's ready
  (spam the key; Auto Shot keeps going in between).
  1.4.0: when the target is in melee range the same key does Raptor Strike
  (plus Mongoose Bite / Counterattack when allowed) - the game refuses the
  shots up close and the melee hits at range, so one key works at any
  distance (/hunt melee turns it off). The aspect now goes up on the same
  press and never switches off, mending / feeding your pet only happens
  with no enemy targeted (targeting one always shoots), and the interrupt
  moved to the end of the key.
  1.5.0: Auto Shot is asked for once per target (and again after a fight)
  instead of on every press - asking again while it's already shooting makes
  the game retry it and delays your shots (the stutter). Every spell the
  game may refuse (cooldown, out of range, too close) now runs from its own
  small button, so a refused one can't stop the rest of the key; Raptor
  Strike comes first and starts your melee swings when you're in range.
  1.5.1: those small buttons now cast their spell directly (1.5.0 used
  small macros, which the game won't run from inside a macro, so the key
  did nothing). The once-per-target Auto Shot is the first line of the key.
  1.6.0: this game ends the whole key press at the first spell it refuses
  (on cooldown, out of range, too close) - even through those buttons - so
  Raptor Strike being refused at range stopped Arcane Shot and Serpent
  Sting. Now the key does: Auto Shot (once per target), pet attack, Hunter's
  Mark -> Serpent Sting (once per target), then ONE spell per press from a
  rotating list: Arcane Shot, Raptor Strike, Concussive Shot, Arcane Shot,
  Raptor Strike, (Mongoose Bite, Counterattack, Kill Command, interrupt).
  A refused one just costs that press - spam the key and each gets its
  turn several times a second. The melee key works the same way. If a mob
  reaches you before Serpent Sting goes out, use the melee key (or back
  off) - Serpent Sting can't be cast in melee range and holds the key up
  until it lands or you change target.
  A new target starts the openers over. Spells you haven't learned are left
  out on their own.

  In combat the game locks keys and hides health and buffs from addons, so
  the order is fixed - it can't re-apply a sting that fell off or react to
  what happens mid-fight. Out of combat it reads everything.

MELEE
  Auto attack + pet attack + Raptor Strike, plus Mongoose Bite (after the
  target dodges) and Counterattack (after you parry, talent) whenever the
  game allows them (1.1.0). Kill Command (after a crit) goes on the Shoot
  key once you know it. /hunt reactives turns these off.
  (The game doesn't let addons check range, so switch keys yourself when
  something reaches you.)

INTERRUPT (1.2.0)
  In a fight the Shoot and Melee keys also fire Intimidation / Silencing
  Shot / Counter Shot (whichever you know) whenever it's ready. Scatter Shot
  is left out (damage breaks it). TwizInterrupt's /interrupt attack turns
  that off.

PET CARE
  Mend / revive / call / feed, whenever you press it.

VENDOR RESTOCK (automatic, at any vendor)
  Ammo: the best arrows (bow, crossbow) or bullets (gun) you can use, up to
  5 stacks. Pet food: the highest level food your pet eats, up to 20.
  Diet is matched by the food's name (the game doesn't tell addons a food's
  diet), so odd names may be missed.

Commands
  /hunt               status
  /hunt aspects       automatic Aspect of the Hawk on/off
  /hunt cheetah       Aspect of the Cheetah with nothing targeted on/off
  /hunt pet           pet care on the Shoot key on/off
  /hunt concussive    Concussive Shot on the Shoot key on/off
  /hunt melee         Raptor Strike on the Shoot key in melee range on/off
  /hunt reactives     Mongoose Bite / Counterattack / Kill Command on/off
  /hunt ammo [n]      ammo restock on/off, or keep n stacks
  /hunt food [n]      pet food restock on/off, or keep n
