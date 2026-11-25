TwizHunt 1.2.1 - one-key hunter
================================

Bind the keys in Options > Keybindings > AddOns > TwizHunt.

SHOOT (the one key)
  Out of combat it first fixes what's missing, one thing per press:
    pet dead -> Revive Pet, no pet -> Call Pet, pet under 60% -> Mend Pet,
    pet unhappy -> Feed Pet with the best food in your bags it eats,
    an enemy targeted without Aspect of the Hawk -> Aspect of the Hawk
    (/hunt cheetah: Aspect of the Cheetah when nothing's targeted).
  Then, on an enemy: Auto Shot + your pet attacks, and on each NEW target
  Hunter's Mark -> Summon Hawk -> Serpent Sting once, then Arcane Shot every
  time it's ready (spam the key; Auto Shot keeps going in between).
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
  /hunt reactives     Mongoose Bite / Counterattack / Kill Command on/off
  /hunt ammo [n]      ammo restock on/off, or keep n stacks
  /hunt food [n]      pet food restock on/off, or keep n
