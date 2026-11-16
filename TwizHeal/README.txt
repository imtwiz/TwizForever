TwizHeal 1.0.0 - one hotkey heals whoever needs it most

Priests, druids, paladins and shamans.

WHO GETS HEALED
  You and your party (or raid). Among everyone missing enough health to be
  worth a heal (below 90%, or missing more than your smallest heal):
    1. tanks, 2. healers, 3. damage dealers - lowest health first in each.
  Anyone in danger (30% or less) is healed first, whatever their role.
  Tanks are whoever has the tank role, whoever enemies are attacking, or
  warriors; healers are those with the healer role, or priests.

WHICH HEAL
  The smallest rank of your direct heal that covers what they're missing
  and that you have the mana for (Lesser Heal / Heal / Greater Heal,
  Healing Touch, Holy Light, Healing Wave). Someone in danger gets your fast
  heal (Flash Heal, Regrowth, Flash of Light, Lesser Healing Wave).
  /th ranks lists your heals with how much each one heals and costs.

USE
  Bind a key: Options > Keybindings > AddOns > TwizHeal.
  Out of combat: press it - it heals TwizHeal's pick with the right rank.
  In combat the game locks what an addon can aim at, so:
    - hover a bar in the TwizHeal window (the gold-bordered one is who
      TwizHeal picks, and the window shows which heal) and press your key -
      it heals the person under your mouse;
    - or have a friendly player targeted - it heals your target;
    - or click a bar to heal that person.
  Hold Shift for your fast heal. Every heal needs a key press or click -
  no addon can cast on its own.

COMMANDS (/th or /twizheal)
  /th               show / hide the window (out of combat)
  /th danger 30     heal anyone at 30% or less first, whatever their role
  /th threshold 90  people below 90% are worth a heal
  /th ranks         list your heals
