TwizWarrior 1.3.2 - one-key warrior
====================================

Bind the keys in Options > Keybindings > AddOns > TwizWarrior.

ATTACK (the one key)
  Auto attack; per target Battle Shout (only when it was missing when the
  fight started) and Rend, once each; Heroic Strike on every press (it waits
  for your next swing, so the other spells still go off); Execute when the
  target is low enough for it; Overpower right after the target dodges (in
  Battle Stance - 1.1.0, /warrior overpower turns it off); Revenge after
  you block, dodge or parry (in Defensive Stance - 1.2.0, /warrior revenge
  turns it off); Victory Rush whenever it's up after a kill.
  Spells you haven't learned are left out. /warrior hs turns the Heroic
  Strike dump off when you're short on rage; /warrior rend, /warrior shout.

  In combat the game locks keys and hides health and buffs, so the order is
  fixed; Execute / Victory Rush that aren't usable yet are just skipped (the
  game may show "not usable" - TwizErrors /terr text hides that).

CHARGE
  Charge out of combat, Intercept in combat (once you know it).

INTERRUPT
  Shield Bash with a shield on, else Pummel. 1.3.0: in a fight the Attack
  key also fires Pummel (Berserker Stance) / Shield Bash (shield, other
  stances) whenever it's ready - the game can't tell a macro whether the
  enemy is casting, so it goes as soon as it's off cooldown. TwizInterrupt's
  /interrupt attack turns that off.

Commands: /warrior (status), /warrior shout, /warrior rend, /warrior hs,
/warrior overpower, /warrior revenge

1.3.2: no "null" at the end of the Battle Shout / Rend sequence anymore -
this game's sequence code errors on it ("Usage: CastSpellByName") and the
error aborts the whole press. Six Heroic Strikes fill the sequence instead,
then Rend comes round again.
