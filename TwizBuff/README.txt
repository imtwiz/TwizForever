TwizBuff 1.3.0 - cast the buffs your friends (and strangers) are missing

Shows who is missing the buffs your class can give, and casts the next one
with one click, key press or mouse-wheel notch.

WHO
  You, your party (or raid), and random friendly players near you: your
  target, whoever is under your mouse, and every friendly player with a
  nameplate. TwizBuff turns friendly nameplates on for this (/tb strangers
  off turns that and the stranger buffing off and puts your nameplate
  setting back). PvP-flagged strangers are buffed too; /tb pvp skips them
  unless you're flagged (buffing them would flag you).

WHAT
  Only spells you know:
    Druid    Mark of the Wild (Gift of the Wild for 3+ in your group)
             Thorns (/tb thorns to leave it out)
    Priest   Power Word: Fortitude (Prayer of Fortitude), Divine Spirit
             (mana users), Shadow Protection (off by default: /tb shadow)
    Mage     Arcane Intellect (Arcane Brilliance) - mana users only
    Paladin  a Blessing: Kings if you have it, else Wisdom for mana users
             and Might for everyone else; anyone with a blessing is skipped
    Warrior  Battle Shout when you don't have it
  When 3 or more people in your group need the same buff and you know the
  group version and have its reagent, it casts that instead.

USE
  The window lists who needs what (out-of-range people are greyed out) and
  the gold button casts the next buff - your target first, then you, then
  your group, then strangers; anyone in range before anyone out of range. The window hides itself when everyone is buffed.
  Spin your mouse wheel to buff: out of combat, while someone in range is
  missing a buff, each wheel notch casts the next one (/tb wheel off gives
  the wheel back to the camera). The game needs a real click/key/wheel notch
  for every cast - no addon can cast on its own - and the button can only
  be re-aimed out of combat.

  Bind a key: Options > Keybindings > AddOns > TwizBuff.

ONE KEY FOR BUFFS AND HEALS (with TwizHeal)
  If TwizHeal is installed, the TwizBuff key (and the mouse wheel) also
  heals:
    - in combat: it heals whoever needs it most (TwizHeal's pick - hover a
      TwizHeal bar to choose, Shift = fast heal, Ctrl = HoT);
    - out of combat: it heals first if someone is hurt, otherwise it casts
      the next missing buff.
  Buffs are only cast out of combat.

COMMANDS (/tb or /twizbuff)
  /tb               show / hide the window
  /tb wheel on|off  cast the next buff with the mouse wheel (on by default;
                    out of combat, only while someone in range needs a buff)
  /tb strangers on|off  buff nearby strangers too (on by default)
  /tb auto          hide the window when everyone is buffed (on by default)
  /tb shadow        include Shadow Protection (priests)
  /tb thorns        leave out / include Thorns (druids)
  /tb pvp           skip PvP-flagged strangers
  /tb group N       use the group version when N or more need it (default 3)
