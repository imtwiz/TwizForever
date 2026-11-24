TwizInterrupt 1.0.0 - interrupts for every class
================================================

Bind the key in Options > Keybindings > AddOns > TwizInterrupt.

INTERRUPT KEY
  Your class's interrupt on the enemy under your mouse, else your target:
    Warrior  Pummel (Berserker Stance), Shield Bash (shield, other stances)
    Rogue    Kick, then Gouge if Kick is on cooldown
    Mage     Counterspell
    Shaman   Wind Shear, Earth Shock
    Priest   Silence
    Warlock  Spell Lock (felhunter out)
    Paladin  Rebuke, Hammer of Justice
    Hunter   Counter Shot, Silencing Shot, Scatter Shot, Intimidation
    Druid    Skull Bash, Bash, Feral Charge (Bear Form)
    Racials  War Stomp, Arcane Torrent
  Only spells you know are used; when the first is on cooldown the next one
  goes off. /interrupt hover off = target only.

ALERT
  The moment your target (or focus) starts casting something you can
  interrupt - and, while you're in a fight, any enemy nameplate near you or
  any enemy casting at you - a big INTERRUPT alert shows who is casting
  what, whether your interrupt is ready and in range, and which key to
  press, with a warning sound. Casts that can't be interrupted are ignored.
  Turn on enemy nameplates (V) to get alerts for enemies you haven't
  targeted; hover them and press the key.

  Why not fully automatic? The game only lets a key press or click cast a
  spell - no addon can cast on its own - so the alert says when and your
  key does it.

Commands
  /interrupt          status (also /tint)
  /interrupt alert    alert on/off
  /interrupt sound    alert sound on/off
  /interrupt nearby   alerts for nearby enemies, not just your target
  /interrupt hover    interrupt the enemy under the mouse first on/off
  /interrupt unlock   move the alert (then /interrupt lock)
  /interrupt test     show a sample alert
