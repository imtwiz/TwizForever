TwizMage 1.0.1 - one-key mage
=============================

Bind the keys in Options > Keybindings > AddOns > TwizMage.

ATTACK (the one key)
  Out of combat it first fixes what's missing, one thing per press:
    - your armor: Ice Armor, else Frost Armor (/mage armor mage|molten|frost
      to pick another, /mage armor off to skip it)
    - with no enemy targeted: conjures water until you have 20, food until
      20, and a mana gem if you have none (/mage water 40, /mage food 10,
      /mage gem, /mage conjure). Press it with nothing targeted to get
      ready between pulls.
  Then on an enemy:
    - in a fight, Counterspell whenever it's ready (TwizInterrupt's
      /interrupt attack turns that off) - a macro can't see whether the
      enemy is casting, so it goes as soon as it's off cooldown
    - Fire Blast whenever it's ready (/mage fireblast turns it off)
    - your main nuke: Frostbolt, or Fireball before you know Frostbolt
      (/mage main fireball | arcane | frostbolt | auto)

  In combat the game locks keys and hides health, mana and buffs, so the
  order is fixed; spells on cooldown are just skipped.

FROST NOVA     Frost Nova.
POLYMORPH      The enemy under your mouse, else your target.
BLINK          Blink.
MANA           In a fight: your mana gem, then Evocation. Out of combat:
               drinks your best conjured water.

REAGENT VENDOR
  Runes of Teleportation (once you know a Teleport) and Runes of Portals
  (once you know a Portal), up to 5 each (/mage restock).

Buffs (Arcane Intellect) are TwizBuff's job; TwizChef's eat/drink key also
uses conjured food and water.

Commands: /mage (status), /mage main, /mage armor, /mage fireblast,
/mage conjure, /mage water [n], /mage food [n], /mage gem, /mage restock
